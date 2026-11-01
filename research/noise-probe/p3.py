import asyncio, base64, json, sys, os, numpy as np, soundfile as sf, websockets
key = [l.split("=",1)[1].strip().strip('"') for l in open(os.path.expanduser("~/Library/Application Support/Aloud/keys.env")) if l.startswith("ELEVENLABS_API_KEY")][0]
clean, _ = sf.read(sys.argv[1], dtype="float32"); babble, _ = sf.read(sys.argv[2], dtype="float32")
async def run(a, extra):
    url = "wss://api.elevenlabs.io/v1/speech-to-text/realtime?model_id=scribe_v2_realtime&audio_format=pcm_16000&commit_strategy=manual&language_code=en" + extra
    async with websockets.connect(url, additional_headers={"xi-api-key": key}) as ws:
        await ws.recv()
        pcm = (np.clip(a, -1, 1) * 32767).astype("<i2").tobytes()
        for i in range(0, len(pcm), 3200):
            await ws.send(json.dumps({"message_type": "input_audio_chunk", "audio_base_64": base64.b64encode(pcm[i:i+3200]).decode(), "commit": i + 3200 >= len(pcm), "sample_rate": 16000})); await asyncio.sleep(0.02)
        while True:
            m = json.loads(await asyncio.wait_for(ws.recv(), 10))
            if m["message_type"].startswith("committed"): return m["text"]
            if "error" in m: return m
K="&keyterms=lol&keyterms=lmao&keyterms=omg&keyterms=btw&keyterms=idk"
async def main():
    rng = np.random.default_rng(1)
    for level in [0, 0.5, 0.9]:
        noise = rng.standard_normal(len(clean)).astype("float32") * 0.05 + np.resize(babble, len(clean)) * 0.8
        a = clean / np.abs(clean).max() * 0.5 + level * noise
        for extra in ["", K, "&filter_background_audio=true", "&filter_background_audio=true"+K]:
            print(level, extra.replace(K,"+KT")[:30].ljust(32), await run(a, extra))
asyncio.run(main())
