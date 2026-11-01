import asyncio, base64, json, sys, os, soundfile as sf, websockets
key = [l.split("=",1)[1].strip().strip('"') for l in open(os.path.expanduser("~/Library/Application Support/Aloud/keys.env")) if l.startswith("ELEVENLABS_API_KEY")][0]
async def run(extra):
    a, sr = sf.read(sys.argv[1], dtype="float32"); print(len(a)/sr, "s")
    url = "wss://api.elevenlabs.io/v1/speech-to-text/realtime?model_id=scribe_v2_realtime&audio_format=pcm_16000&commit_strategy=manual&language_code=en" + extra
    async with websockets.connect(url, additional_headers={"xi-api-key": key}) as ws:
        print(" <", (await ws.recv())[:200])
        pcm = (a * 32767).astype("<i2").tobytes()
        for i in range(0, len(pcm), 3200):
            await ws.send(json.dumps({"message_type": "input_audio_chunk", "audio_base_64": base64.b64encode(pcm[i:i+3200]).decode(), "commit": i + 3200 >= len(pcm), "sample_rate": 16000})); await asyncio.sleep(0.1)
        try:
            while True: print(" <", (await asyncio.wait_for(ws.recv(), 8))[:600])
        except Exception as e: print(" end", repr(e)[:200])
for extra in ["", "&include_timestamps=true", "&filter_background_audio=true"]:
    print(extra); asyncio.run(run(extra))
