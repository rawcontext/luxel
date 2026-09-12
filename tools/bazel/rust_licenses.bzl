"""Collect license inputs from the resolved Rust graph, including build dependencies."""

RustLicenseInputsInfo = provider("Declared manifests and notices from Rust package dependencies.", fields = ["files", "manifests"])
_EDGES = ["deps", "proc_macro_deps", "crate", "binary", "actual"]
_NOTICE_FILES = ["Cargo.toml", "LICENSE", "LICENSE-MIT", "LICENSE-UNICODE", "COPYRIGHT", "NOTICE"]

def _licenses_aspect_impl(_target, ctx):
    transitive_files = []
    transitive_manifests = []
    if not ctx.rule:
        return [RustLicenseInputsInfo(files = depset(), manifests = depset())]
    for edge in _EDGES:
        dependencies = getattr(ctx.rule.attr, edge, [])
        if type(dependencies) == "Target":
            dependencies = [dependencies]
        for dependency in dependencies:
            if RustLicenseInputsInfo in dependency:
                transitive_files.append(dependency[RustLicenseInputsInfo].files)
                transitive_manifests.append(dependency[RustLicenseInputsInfo].manifests)
    files = []
    manifests = []
    if "cargo-bazel" in getattr(ctx.rule.attr, "tags", []):
        root = ctx.label.workspace_root
        for file in getattr(ctx.rule.files, "compile_data", []):
            if file.dirname == root and file.basename in _NOTICE_FILES:
                files.append(file)
                if file.basename == "Cargo.toml":
                    manifests.append(file)
    return [RustLicenseInputsInfo(
        files = depset(files, transitive = transitive_files),
        manifests = depset(manifests, transitive = transitive_manifests),
    )]

_licenses_aspect = aspect(implementation = _licenses_aspect_impl, attr_aspects = _EDGES)

def _rust_license_inputs_impl(ctx):
    inputs = [target[RustLicenseInputsInfo] for target in ctx.attr.targets]
    manifests = depset(transitive = [info.manifests for info in inputs])
    files = depset(transitive = [info.files for info in inputs])
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(output, json.encode(sorted([file.path for file in manifests.to_list()])))
    return [DefaultInfo(files = depset([output])), OutputGroupInfo(sources = files)]

rust_license_inputs = rule(
    implementation = _rust_license_inputs_impl,
    attrs = {"targets": attr.label_list(aspects = [_licenses_aspect], mandatory = True)},
)
