import { afterEach, describe, expect, mock, test } from "bun:test";

import { POST } from "../src/pages/api/support";

const originalFetch = globalThis.fetch;
const originalEnvironment = { ...process.env };

afterEach(() => {
  globalThis.fetch = originalFetch;
  for (const name of ["GITHUB_SUPPORT_TOKEN", "GITHUB_SUPPORT_REPO", "TURNSTILE_SECRET_KEY"]) {
    if (originalEnvironment[name] === undefined) {
      delete process.env[name];
    } else {
      process.env[name] = originalEnvironment[name];
    }
  }
});

function submit() {
  process.env.GITHUB_SUPPORT_TOKEN = "test-token";
  process.env.TURNSTILE_SECRET_KEY = "test-secret";
  const form = new FormData();
  form.set("email", "customer@example.com");
  form.set("message", "Please help with my recording.");
  form.set("cf-turnstile-response", "test-challenge");
  const request = new Request("https://luxel.media/api/support", { method: "POST", body: form });
  return POST({ request } as Parameters<typeof POST>[0]);
}

function mockGitHub(repositoryResponse: () => Response) {
  const requests: { url: string; init?: RequestInit }[] = [];
  globalThis.fetch = mock(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    requests.push({ url, init });
    if (url.includes("turnstile")) return Response.json({ success: true });
    if (init?.method === "POST") return Response.json({ html_url: "https://github.com/private/issue" }, { status: 201 });
    return repositoryResponse();
  }) as typeof fetch;
  return requests;
}

describe("private support submissions", () => {
  test("sends contact details only after confirming the default support repository is private", async () => {
    delete process.env.GITHUB_SUPPORT_REPO;
    const requests = mockGitHub(() => Response.json({ private: true }));

    const response = await submit();

    expect(response.status).toBe(201);
    expect(requests[1].url).toBe("https://api.github.com/repos/ccheney/luxel-support");
    expect(requests[1].init?.body).toBeUndefined();
    expect(requests[2].url).toBe(`${requests[1].url}/issues`);
    expect(requests[2].init?.redirect).toBe("error");
    expect(JSON.parse(String(requests[2].init?.body)).body).toContain("customer@example.com");
    expect(await response.text()).not.toContain("customer@example.com");
  });

  test.each([
    ["public", () => Response.json({ private: false })],
    ["unknown visibility", () => Response.json({})],
    ["inaccessible", () => new Response(null, { status: 404 })],
    ["invalid response", () => new Response("not JSON")],
    ["network failure", () => { throw new Error("unavailable"); }]
  ])("does not send personal details when the repository is %s", async (_name, repositoryResponse) => {
    process.env.GITHUB_SUPPORT_REPO = "owner/configured-support";
    const requests = mockGitHub(repositoryResponse);

    expect((await submit()).status).toBe(502);
    expect(requests).toHaveLength(2);
    expect(requests[1].url).toBe("https://api.github.com/repos/owner/configured-support");
    expect(requests[1].init?.body).toBeUndefined();
  });

  test("rejects a malformed destination before contacting GitHub", async () => {
    process.env.GITHUB_SUPPORT_REPO = "owner/repo/issues";
    const requests = mockGitHub(() => Response.json({ private: true }));

    expect((await submit()).status).toBe(502);
    expect(requests).toHaveLength(1);
  });
});
