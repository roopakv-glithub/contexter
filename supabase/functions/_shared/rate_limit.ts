export async function consumeAiRequest(request: Request): Promise<boolean> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("Supabase function environment is not configured.");
  }

  const forwardedFor = request.headers.get("x-forwarded-for");
  const clientAddress = request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-real-ip") ??
    forwardedFor?.split(",").at(-1)?.trim() ??
    "unknown";
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(clientAddress),
  );
  const clientHash = Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");

  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/consume_ai_request`, {
    method: "POST",
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_client_hash: clientHash }),
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`Could not verify the AI usage limit (${response.status}). Apply the Supabase database migrations and retry.`);
  }
  const allowed = await response.json();
  if (typeof allowed !== "boolean") {
    throw new Error("Supabase returned an invalid AI usage limit response.");
  }
  return allowed;
}

export function rateLimitResponse(corsHeaders: Record<string, string>): Response {
  return Response.json(
    { error: "AI usage limit reached. Please wait a minute and try again." },
    { status: 429, headers: corsHeaders },
  );
}
