"""Check the generated Shelf SBOM against the lockfile and Hex archive."""

import io
import json
import tarfile
import tomllib
from pathlib import Path


def main():
    project = tomllib.loads(Path("gleam.toml").read_text())
    manifest = tomllib.loads(Path("manifest.toml").read_text())
    snapshot = Path("priv/shelf.cdx.json").read_bytes()
    document = json.loads(snapshot)
    assert document["bomFormat"] == "CycloneDX"
    assert document["specVersion"] == "1.6"
    assert document["metadata"]["timestamp"] == "1970-01-01T00:00:00Z"
    root = document["metadata"]["component"]
    assert root["name"] == project["name"]
    assert root["version"] == project["version"]
    assert root["description"] == project["description"]
    assert {entry["license"]["id"] for entry in root["licenses"]} == set(
        project["licences"]
    )
    assert all(
        entry["license"]["acknowledgement"] == "declared" for entry in root["licenses"]
    )

    packages = {package["name"]: package for package in manifest["packages"]}
    components = {component["name"]: component for component in document["components"]}
    assert len(components) == len(document["components"])
    assert components.keys() == packages.keys()
    assert "licence_audit" not in manifest["requirements"]
    production = set(project["dependencies"])
    pending = list(production)
    while pending:
        for dependency in packages[pending.pop()]["requirements"]:
            if dependency not in production:
                production.add(dependency)
                pending.append(dependency)

    references = {}
    for name, package in packages.items():
        component = components[name]
        assert package["source"] == "hex"
        assert component["version"] == package["version"], name
        assert component["scope"] == (
            "required" if name in production else "optional"
        ), name
        assert component["purl"] == f"pkg:hex/{name}@{package['version']}", name
        assert component["hashes"] == [
            {"alg": "SHA-256", "content": package["outer_checksum"].lower()}
        ], name
        assert component["licenses"], name
        assert all(
            entry["license"]["acknowledgement"] == "declared"
            for entry in component["licenses"]
        ), name
        references[name] = component["bom-ref"]
        assert component["bom-ref"] == component["purl"], name

    expected_graph = {
        references[name]: {
            references[dependency] for dependency in package["requirements"]
        }
        for name, package in packages.items()
    }
    expected_graph[root["bom-ref"]] = {
        references[name] for name in manifest["requirements"]
    }
    graph = {
        entry["ref"]: set(entry["dependsOn"]) for entry in document["dependencies"]
    }
    assert len(graph) == len(document["dependencies"])
    assert graph == expected_graph

    archive = Path("build") / f"{project['name']}-{project['version']}.tar"
    with (
        tarfile.open(archive) as outer,
        tarfile.open(
            fileobj=io.BytesIO(outer.extractfile("contents.tar.gz").read()),
            mode="r:gz",
        ) as contents,
    ):
        assert contents.extractfile("priv/shelf.cdx.json").read() == snapshot
        packaged = tomllib.loads(contents.extractfile("gleam.toml").read().decode())
        assert packaged["name"] == project["name"]
        assert packaged["version"] == project["version"]
        assert packaged["dependencies"] == project["dependencies"]
        assert all(
            source.as_posix() in contents.getnames()
            for source in Path("src").rglob("*")
            if source.is_file()
        )
    print(
        f"Verified {len(packages)} locked components "
        f"({len(production)} required), dependency graph, and packaged SBOM bytes."
    )


if __name__ == "__main__":
    main()
