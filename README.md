# annkedetect

Flags the people, animals and vehicles seen in the camera archive's clips (those `annkepull` fetches), for
`annkeserv` to show. A long-running worker at idle priority: it works through the clips that have no
result yet, newest first, so a new clip is flagged soon after it arrives and the backlog is done in the
gaps; it looks for new clips every `rescan` seconds (default an hour: annkepull brings them once a day).

Per clip it decodes the keyframes (one every 2-3 s), runs an object detector on each -- YOLOX-S trained on
COCO, from the OpenCV model zoo, through ONNX Runtime -- and writes beside the clip:

| | |
|---|---|
| `recording_<...>.json` | `{"seen": {"people": 0.85, "animals": 0.47}, "detections": [...], "ignored": [...], ...}` -- written last, so it marks the clip done |
| `recording_<...>.jpg` | only when something was seen: the keyframe with the best detection, 640 wide, boxes drawn (people red, animals yellow, vehicles cyan) |

`seen` is the best score per group; `detections` lists each one counted (`t` seconds into the clip, class,
score, box in the clip's pixels) and `ignored` those left out, with `why` (`zone` or `static`). To have
clips done again -- after changing masks or settings -- remove their `.json`.

| | |
|---|---|
| `annkedetect` | the tool (Node; one npm dependency, `onnxruntime-node`; uses `ffmpeg`, `ffprobe`) |
| `annkedetect.service` | the worker, `Nice=19`, `CPUSchedulingPolicy=idle`, `IOSchedulingClass=idle` |
| `annkedetect-storage.service` | gate: it needs `opt-storage-disk.mount` |

## What counts

- **Groups, not species.** People; animals (bird, cat, dog, horse, sheep, cow); vehicles (bicycle, car,
  motorcycle, bus, truck). At these distances the species is often wrong -- a white dog and a cat both
  scored as "sheep" -- while the group is right. A tractor comes out as a truck.
- **Zones.** With `masks=<dir>`, a detection counts only where its bottom centre (feet, wheels) is white in
  `<camera>-mask.png` (every group) or `<camera>-mask-<group>[-and-<group>].png` (`cars` is vehicles); a
  group's own mask overrides the general one for that group, so `side-mask-vehicles.png` can paint out
  fixed clutter that is only ever mistaken for a vehicle while people and animals keep `side-mask.png`.
  Only the part of the frame the masks cover is decoded and searched. Paint masks over a full-size
  snapshot of the camera; any size of the same shape works. They are re-read when they change.
- **Not parked.** A vehicle in the same place in every keyframe is ignored (something parked, or a round
  lid the model took for a car): the cameras record on motion, so what set the clip off moves. People and
  animals standing still still count.
- **Detail.** The model sees 640x640. `tiles-<camera>=2` searches overlapping 640 px tiles of a frame
  scaled to two tiles wide: four times the pixels per object for about twice the time. On side, at one
  tile, a dog (0.18) and a cat in the yard were missed; at two they were found (0.47, 0.68).
- `threshold` (default 0.4) is the score a detection needs. Lowering it on side brought the brick stacks
  and pallets in as "cars" well before it found the dog.
- **Not a known false positive.** See below.

## False positives

Some things are taken for something else again and again, but not in every keyframe, so the "not parked"
rule misses them: on side, the lid of the waste tank is a "car" (0.41-0.69) in one keyframe of a clip
here and there, always in much the same box. To screen one out, copy a result that shows it into the
`screens` folder:

```sh
cp /opt/storage/camera/side/20261006/recording_20261006131456.json /opt/annkedetect/annkedetect.workshop/screens/
```

Every detection in a file there becomes a known false positive for that result's camera (if the clip also
caught something real, delete that entry from the copy). A detection counts as the same when it is of the
same group on the same camera and in the same place: its box's centre inside the false positive's box, at
no more than twice or half its size. (Not box overlap: on a small, distant box a shift of a few pixels
halves it -- a turquoise thing at the back of side's view, 98x29 one day and 131x32 the next, overlapped by
0.39.) A person by the lid is a different group, so still counts. A matched detection is listed in
`ignored` with `"why": "screen"` and the file it matched.

When the folder changes, every result already written is checked against it again -- from what the
result recorded, without detecting again -- so dropping a file in clears the past too, and taking it out
brings those detections back; thumbnails are redrawn or removed to match. Which screens the archive was
last checked against is kept in `/var/lib/annkedetect`, so a restart does not check it all again.

## Cost

On workshop (Celeron 847, 2 cores, no AVX): ~0.4 s to decode a 4K HEVC keyframe and ~3.7 s per 640 px
search. So ~15-20 s per front clip (whole frame) and ~25-35 s per side clip (two tiles), ~45 minutes a day
for both cameras, and a few days for the whole archive. `days=<n>` limits it to recent clips.

## Install

```sh
make install      # model (fetched, checksummed), tool + npm dependency to /usr/local/lib/annkedetect, config, units
make status       # the worker and its last log lines
make test CLIP="/opt/storage/camera/side/<YYYYMMDD>/recording_<...>.mp4"   # what a clip would get, writing nothing
```

Config goes to `/etc/default/annkedetect`; a per-host `annkedetect.<hostname>.cfg` is used instead of
`annkedetect.cfg` when present. A host's masks can sit beside it in `annkedetect.<hostname>/` (with the
snapshots they were painted on); like the per-host config, that folder is not committed.

## Notes

- The model expects BGR, 0..255, unnormalised, letterboxed with 114, and its output is per anchor of
  80x80/40x40/20x20 grids (strides 8/16/32): centre and size in cells, objectness, then the 80 COCO
  class scores. Decoding and non-maximum suppression are done here.
- ONNX Runtime's prebuilt binaries run on this CPU without AVX (TensorFlow's and recent PyTorch's need it);
  `make install` keeps only the linux/x64 ones.
- Keyframe times come from the packet flags (`ffprobe -show_entries packet`), without decoding.

## License

CC BY-NC-SA 4.0 — see [LICENSE](LICENSE).
