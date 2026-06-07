export type ZApiKeyScope = string;

const API_KEY_FULL_ACCESS_SCOPE = "fullaccess";

function apiKeyScopesGrantScope(
  grantedScopes: ZApiKeyScope[],
  requiredScope: ZApiKeyScope,
) {
  if (grantedScopes.includes(API_KEY_FULL_ACCESS_SCOPE)) {
    return true;
  }
  if (grantedScopes.includes(requiredScope)) {
    return true;
  }
  const readWriteScope = requiredScope.endsWith(":read")
    ? requiredScope.replace(/:read$/, ":readwrite")
    : null;
  return readWriteScope ? grantedScopes.includes(readWriteScope) : false;
}

export async function fetchApiKeyScopes(
  addr: string,
  apiKey: string,
): Promise<ZApiKeyScope[]> {
  try {
    const res = await fetch(`${addr}/api/v1/auth/me`, {
      headers: {
        authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
    });
    if (!res.ok) return [];
    const data = (await res.json()) as { auth?: { scopes?: string[] } };
    return data.auth?.scopes ?? [];
  } catch (e) {
    console.error("Failed to fetch API key scopes:", e);
    return [];
  }
}

export function hasScope(
  scopes: ZApiKeyScope[],
  required: ZApiKeyScope,
): boolean {
  if (scopes.length === 0) return true;
  return apiKeyScopesGrantScope(scopes, required);
}
