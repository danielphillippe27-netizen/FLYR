function escapeHTML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const token = url.searchParams.get("token")?.trim();
  const appURL = token ? `flyr://join?token=${encodeURIComponent(token)}` : "flyr://join";

  const body = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Open FLYR Invite</title>
    ${
      token
        ? `<script>
      const appURL = ${JSON.stringify(appURL)};
      const tryOpenApp = () => {
        window.location.href = appURL;
      };
      window.addEventListener("load", () => {
        setTimeout(tryOpenApp, 150);
      });
    </script>`
        : ""
    }
    <style>
      :root {
        color-scheme: dark;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      }
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background: #111111;
        color: #f5f5f5;
      }
      main {
        width: min(32rem, calc(100vw - 2rem));
        padding: 2rem;
        border-radius: 16px;
        background: #191919;
        box-sizing: border-box;
      }
      h1 {
        margin: 0 0 0.75rem;
        font-size: 1.75rem;
      }
      p {
        margin: 0 0 1rem;
        line-height: 1.5;
        color: #cfcfcf;
      }
      a.button {
        display: inline-block;
        margin-top: 0.5rem;
        padding: 0.9rem 1.1rem;
        border-radius: 8px;
        background: #f04f4f;
        color: #ffffff;
        text-decoration: none;
        font-weight: 600;
      }
      .small {
        margin-top: 1rem;
        font-size: 0.95rem;
        color: #a9a9a9;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>${token ? "Join this session in FLYR" : "Invite link missing"}</h1>
      <p>${
        token
          ? "Open the app to join the live session and jump straight onto the map."
          : "This invite link is missing its token. Ask your teammate to send a fresh one."
      }</p>
      ${
        token
          ? `<a class="button" href="${escapeHTML(appURL)}" onclick="window.location.href='${escapeHTML(
              appURL
            )}'; return false;">Join session</a>
      <p class="small">If you are opening this from an in-app browser, tap again or open the link in Safari.</p>`
          : ""
      }
    </main>
  </body>
</html>`;

  return new Response(body, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}
