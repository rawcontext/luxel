"""Include the operating-system runtime identity in native integration-test keys."""

def _host_runtime_impl(ctx):
    if ctx.os.name == "mac os x":
        version = ctx.read("/System/Library/CoreServices/SystemVersion.plist", watch = "yes")
    else:
        version = ctx.execute(["uname", "-sr"]).stdout
    ctx.file("runtime.json", json.encode({"os": ctx.os.name, "arch": ctx.os.arch, "version": version}))
    ctx.file("BUILD.bazel", "exports_files([\"runtime.json\"], visibility = [\"//visibility:public\"])")

host_runtime = repository_rule(implementation = _host_runtime_impl, local = True, configure = True)
