"""Prepare deterministic bundle metadata for the selected distribution."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _app_metadata_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".plist")
    mode = "app-store" if ctx.attr.app_store[BuildSettingInfo].value else "development"
    ctx.actions.run(
        executable = ctx.executable._tool,
        inputs = [ctx.file.src],
        outputs = [output],
        arguments = [ctx.file.src.path, output.path, mode],
        mnemonic = "AppMetadata",
    )
    return [DefaultInfo(files = depset([output]))]

app_metadata = rule(
    implementation = _app_metadata_impl,
    attrs = {
        "src": attr.label(allow_single_file = True, mandatory = True),
        "app_store": attr.label(mandatory = True),
        "_tool": attr.label(default = "//tools/bazel:prepare_app_metadata", executable = True, cfg = "exec"),
    },
)
