import installer from "../../installer/install.sh?raw";

export const prerender = true;

export function GET() {
  return new Response(installer, {
    headers: {
      "Cache-Control": "public, max-age=300",
      "Content-Type": "text/x-shellscript; charset=utf-8"
    }
  });
}
