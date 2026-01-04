## Audio files

Firstly, record your audio files with a voice recorder of your choice, preferably in `.wav` format. Place the audio files on your server in the folder `/tmp`.

After you have your audio files ready, transcode them to the formats `G.722`, `ALAW` and `ULAW` using the steps below.

### Step 1: Convert to G.722 using ffmpeg

If you don’t have ffmpeg installed, install it using the following command:

```bash
sudo apt-get update
sudo apt-get install ffmpeg
```

Then proceed with the transcoding:

```bash
ffmpeg -i source.wav -ar 16000 -acodec g722 -ac 1 output.g722
```

### Step 2: Convert to ALAW and ULAW using sox

If you don’t have sox installed, install it using the following command:

```bash
sudo apt-get update
sudo apt-get install sox
```

Then proceed with the transcoding:

```bash
sox source.wav -r 8000 -c 1 -t al output.alaw
sox source.wav -r 8000 -c 1 -t ul output.ulaw
```

### Step 3: Place output files in the correct folder

Asterisk stores the sound files in different folders for different languages, for example:

- /data/sounds/en/ for English sound files
- /data/sounds/de/ for German sound files

Place your sound files accordingly to use them during your IVR menu.
