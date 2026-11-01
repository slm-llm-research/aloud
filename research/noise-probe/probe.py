import asyncio, base64, json, sys, os, numpy as np, soundfile as sf, websockets, itertools
key = [l.split("=",1)[1].strip().strip('"') for l in open(os.path.expanduser("~/Library/Application Support/Aloud/keys.env")) if l.startswith("ELEVENLABS_API_KEY")][0]
async def run(path, noise, params):
    a, sr = sf.read(path, dtype="float32")
    if noise:
        rng = np.random.default_rng(0)
        # babble-ish: pink noise plus a second voice from the meeting clip
        n = rng.standard_normal(len(a)).astype("float32"); n = np.convolve(n, np.ones(8)/8, "same")
        other, _ = sf.read(sys.argv[2], dtype="float32"); other = np.resize(other, len(a))
        a = a + noise * (n / np.abs(n).max() * 0.5 + other * 0.6)
        a = np.clip(a, -1, 1)
    url = "wss://api.elevenlabs.io/v1/speech-to-text/realtime?model_id=scribe_v2_realtime&audio_format=pcm_16000&commit_strategy=manual&language_code=en" + "".join(f"&{k}={v}" for k, v in params.items())
    async with websockets.connect(url, additional_headers={"xi-api-key": key}) as ws:
        pcm = (a * 32767).astype("<i2").tobytes()
        for i in range(0, len(pcm), 3200):
            await ws.send(json.dumps({"message_type": "input_audio_chunk", "audio_base_64": base64.b64encode(pcm[i:i+3200]).decode(), "commit": i + 3200 >= len(pcm), "sample_rate": 16000})); await asyncio.sleep(0.02)
        out = []
        while True:
            m = json.loads(await asyncio.wait_for(ws.recv(), 15))
            t = m.get("message_type")
            if t.startswith("committed"):
                words = [(w["text"], round(w.get("logprob", 0), 2)) for w in (m.get("words") or []) if w.get("type") == "word"]
                out.append((t, m.get("text"), words))
                if t == "committed_transcript_with_timestamps" or "include_timestamps" not in params: 
                    if len(out) >= (2 if "include_timestamps" in params else 1): break
            elif "error" in t: out.append((t, m)); break
        return out
async def main():
    for noise in [0, 0.35]:
        for params in [{"include_timestamps": "true"}, {"include_timestamps": "true", "filter_background_audio": "true"}]:
            try: r = await run(sys.argv[1], noise, params)
            except Exception as e: r = repr(e)
            print("noise", noise, params, "\n  ", r)
asyncio.run(main())
