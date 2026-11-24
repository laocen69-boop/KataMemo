export async function onRequestPost(context) {
  const { request, env } = context;
  try {
    const data = await request.json();
    if (!data || typeof data !== 'object') {
      return Response.json({ ok: false, error: 'invalid_payload' }, { status: 400 });
    }
    const record = {
      ts: new Date().toISOString(),
      q1: String(data.q1 || '').slice(0, 120),
      q2: String(data.q2 || '').slice(0, 120),
      q3: Array.isArray(data.q3) ? data.q3.slice(0, 10).map(String) : [],
      q4: Array.isArray(data.q4) ? data.q4.slice(0, 10).map(String) : [],
      q4_words: String(data.q4_words || '').slice(0, 2000),
      q5: String(data.q5 || '').slice(0, 2000),
      q6: String(data.q6 || '').slice(0, 2000),
      ua: String(data.ua || '').slice(0, 300),
    };
    const key = `fb_${Date.now()}_${crypto.randomUUID().slice(0, 6)}`;
    await env.KATAMEMO_FEEDBACK.put(key, JSON.stringify(record));
    return Response.json({ ok: true, id: key });
  } catch (err) {
    return Response.json({ ok: false, error: String(err) }, { status: 500 });
  }
}
