export async function consumeAiRequest(request: Request): Promise<boolean> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = request.headers.get("Authorization");
  if (!supabaseUrl || !anonKey || !authorization) {
    throw new Error("Authenticated Supabase function environment is not configured.");
  }

  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/consume_ai_request`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: authorization,
      "Content-Type": "application/json",
    },
    body: "{}",
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
