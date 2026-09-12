"""Track public website configuration without invalidating other applications."""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def _web_config_impl(ctx):
    output = ctx.actions.declare_file("build-config.json")
    ctx.actions.write(output, json.encode({
        "siteUrl": ctx.attr.site_url[BuildSettingInfo].value,
        "turnstileSiteKey": ctx.attr.turnstile_site_key[BuildSettingInfo].value,
    }))
    return [DefaultInfo(files = depset([output]))]

web_config = rule(
    implementation = _web_config_impl,
    attrs = {
        "site_url": attr.label(mandatory = True),
        "turnstile_site_key": attr.label(mandatory = True),
    },
)
