import type { APIRoute } from "astro";

export const prerender = false;

const defaultRepository = "ccheney/luxel";
const supportAssignee = "ccheney";
const maxMessageLength = 8000;
const maxEmailLength = 254;

type TurnstileResponse = {
  success: boolean;
  "error-codes"?: string[];
};

type GitHubIssueResponse = {
  html_url?: string;
  message?: string;
};

export const POST: APIRoute = async ({ request }) => {
  if (request.method !== "POST") {
    return json({ message: "Method not allowed." }, 405);
  }

  let formData: FormData;
  try {
    formData = await request.formData();
  } catch {
    return json({ message: "Could not read the support request." }, 400);
  }

  const email = stringField(formData, "email");
  const message = stringField(formData, "message");
  const turnstileToken = stringField(formData, "cf-turnstile-response");

  if (!email || !message) {
    return json({ message: "Email and message are required." }, 400);
  }

  if (email.length > maxEmailLength || !isEmail(email)) {
    return json({ message: "Enter a valid email address." }, 400);
  }

  if (message.length > maxMessageLength) {
    return json({ message: "Message is too long." }, 400);
  }

  const turnstileSecret = process.env.TURNSTILE_SECRET_KEY;
  if (!turnstileSecret) {
    return json({ message: "Support submissions are not configured yet." }, 503);
  }

  const turnstileResult = await verifyTurnstile({
    token: turnstileToken,
    secret: turnstileSecret,
    remoteIp: clientIp(request)
  });

  if (!turnstileResult.success) {
    return json({ message: "Please complete the anti-spam check and try again." }, 400);
  }

  const githubToken = process.env.GITHUB_SUPPORT_TOKEN;
  if (!githubToken) {
    return json({ message: "Support submissions are not configured yet." }, 503);
  }

  const repository = process.env.GITHUB_SUPPORT_REPO || defaultRepository;
  const createdIssue = await createGitHubIssue({
    repository,
    token: githubToken,
    email,
    message,
    origin: request.headers.get("origin")
  });

  if (!createdIssue.ok) {
    return json({ message: "Could not create the support request. Please try again later." }, 502);
  }

  return json({ message: "Report sent." }, 201);
};

function stringField(formData: FormData, key: string): string {
  const value = formData.get(key);
  return typeof value === "string" ? value.trim() : "";
}

function isEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function clientIp(request: Request): string | undefined {
  const forwardedFor = request.headers.get("x-forwarded-for");
  return forwardedFor?.split(",")[0]?.trim() || undefined;
}

async function verifyTurnstile({
  token,
  secret,
  remoteIp
}: {
  token: string;
  secret: string;
  remoteIp?: string;
}): Promise<TurnstileResponse> {
  if (!token) {
    return { success: false, "error-codes": ["missing-input-response"] };
  }

  const response = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      secret,
      response: token,
      remoteip: remoteIp
    })
  });

  if (!response.ok) {
    return { success: false, "error-codes": ["siteverify-request-failed"] };
  }

  return response.json() as Promise<TurnstileResponse>;
}

async function createGitHubIssue({
  repository,
  token,
  email,
  message,
  origin
}: {
  repository: string;
  token: string;
  email: string;
  message: string;
  origin: string | null;
}): Promise<Response> {
  const [owner, repo] = repository.split("/");
  if (!owner || !repo) {
    return new Response(null, { status: 500 });
  }

  const response = await fetch(`https://api.github.com/repos/${owner}/${repo}/issues`, {
    method: "POST",
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "User-Agent": "luxel-support-form",
      "X-GitHub-Api-Version": "2022-11-28"
    },
    body: JSON.stringify({
      title: supportTitle(message),
      body: supportBody({ email, message, origin }),
      assignees: [supportAssignee]
    })
  });

  if (!response.ok) {
    return response;
  }

  const issue = await response.json() as GitHubIssueResponse;
  return new Response(JSON.stringify(issue), { status: response.status });
}

function supportTitle(message: string): string {
  const firstLine = message.split(/\r?\n/).find((line) => line.trim())?.trim() ?? "Support request";
  const summary = firstLine.length > 82 ? `${firstLine.slice(0, 79)}...` : firstLine;
  return `Support: ${summary}`;
}

function supportBody({
  email,
  message,
  origin
}: {
  email: string;
  message: string;
  origin: string | null;
}): string {
  return [
    `@${supportAssignee}`,
    "",
    "Support request submitted from the Luxel website.",
    "",
    "## Contact email",
    email,
    "",
    "## Message",
    "```text",
    message.replaceAll("```", "`\u200b``"),
    "```",
    "",
    "## Metadata",
    `- Submitted: ${new Date().toISOString()}`,
    `- Origin: ${origin || "unknown"}`
  ].join("\n");
}

function json(payload: { message: string }, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store"
    }
  });
}
