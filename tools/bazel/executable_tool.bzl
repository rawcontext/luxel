"""Expose a pinned executable in the execution configuration."""

def _executable_tool_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(output = executable, target_file = ctx.file.binary, is_executable = True)
    return [DefaultInfo(executable = executable, runfiles = ctx.runfiles(files = [ctx.file.binary]))]

executable_tool = rule(
    implementation = _executable_tool_impl,
    executable = True,
    attrs = {"binary": attr.label(allow_single_file = True, cfg = "exec", mandatory = True)},
)
