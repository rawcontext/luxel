"""Write declared input names for tools that accept file lists."""

def _file_manifest_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".json")
    paths = [
        file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path
        for file in ctx.files.srcs
    ]
    ctx.actions.write(output, json.encode(sorted(paths)))
    return [DefaultInfo(files = depset([output]), runfiles = ctx.runfiles(files = ctx.files.srcs))]

file_manifest = rule(
    implementation = _file_manifest_impl,
    attrs = {"srcs": attr.label_list(allow_files = True)},
)
