"""Attach cacheable validation actions without shipping their marker files."""

def _validated_files_impl(ctx):
    files = depset(transitive = [source[DefaultInfo].files for source in ctx.attr.srcs])
    checks = depset(transitive = [check[DefaultInfo].files for check in ctx.attr.checks])
    return [DefaultInfo(files = files), OutputGroupInfo(_validation = checks)]

validated_files = rule(
    implementation = _validated_files_impl,
    attrs = {"srcs": attr.label_list(), "checks": attr.label_list()},
)
