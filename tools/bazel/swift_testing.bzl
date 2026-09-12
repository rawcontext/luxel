"""Run native Swift Testing binaries with writable, declared test fixtures."""

def _runfile_path(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    return ctx.workspace_name + "/" + file.short_path

def _swift_testing_impl(ctx):
    binary = ctx.attr.binary[DefaultInfo].files_to_run.executable
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = script,
        substitutions = {
            "{BINARY}": _runfile_path(ctx, binary),
            "{RESOURCES}": _runfile_path(ctx, ctx.file.resources),
            "{SNAPSHOT}": _runfile_path(ctx, ctx.file.snapshot),
            "{XCODE_LOCATOR}": _runfile_path(ctx, ctx.file._xcode_locator),
        },
        is_executable = True,
    )
    runfiles = ctx.runfiles(files = [binary, ctx.file.resources, ctx.file.snapshot, ctx.file._xcode_locator, ctx.file._runtime])
    runfiles = runfiles.merge(ctx.attr.binary[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge(ctx.attr._runfiles[DefaultInfo].default_runfiles)
    environment = ctx.attr.binary[RunEnvironmentInfo]
    return [
        DefaultInfo(executable = script, runfiles = runfiles),
        RunEnvironmentInfo(environment = environment.environment, inherited_environment = environment.inherited_environment),
        ctx.attr.binary[testing.ExecutionInfo],
        coverage_common.instrumented_files_info(ctx, dependency_attributes = ["binary"]),
    ]

swift_testing_test = rule(
    implementation = _swift_testing_impl,
    test = True,
    attrs = {
        "binary": attr.label(mandatory = True),
        "resources": attr.label(allow_single_file = True, mandatory = True),
        "snapshot": attr.label(allow_single_file = True, mandatory = True),
        "_template": attr.label(default = "//tools/bazel:run-swift-tests.sh.tpl", allow_single_file = True),
        "_runfiles": attr.label(default = "@bazel_tools//tools/bash/runfiles"),
        "_xcode_locator": attr.label(default = "@bazel_tools//tools/osx:xcode-locator", allow_single_file = True, cfg = "exec"),
        "_runtime": attr.label(default = "@host_runtime//:runtime.json", allow_single_file = True),
    },
)

def _test_resources_impl(ctx):
    output = ctx.actions.declare_directory(ctx.label.name)
    args = ctx.actions.args()
    args.add(output.path)
    args.add(ctx.file.catalog.path)
    args.add(ctx.file.compiler.path)
    args.add_all(ctx.files.fixtures)
    ctx.actions.run(
        executable = ctx.executable._builder,
        inputs = [ctx.file.catalog, ctx.file.compiler] + ctx.files.fixtures,
        outputs = [output],
        arguments = [args],
        mnemonic = "SwiftTestResources",
    )
    return [DefaultInfo(files = depset([output]))]

swift_test_resources = rule(
    implementation = _test_resources_impl,
    attrs = {
        "catalog": attr.label(allow_single_file = True, mandatory = True),
        "compiler": attr.label(allow_single_file = True, mandatory = True),
        "fixtures": attr.label_list(allow_files = True),
        "_builder": attr.label(default = "//tools/bazel:prepare_test_resources", executable = True, cfg = "exec"),
    },
)
