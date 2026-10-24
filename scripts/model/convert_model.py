#!/usr/bin/env python3
"""Rebuild the bundled Kanto classifier from its pinned upstream checkpoint.

Run in an isolated Python 3.11 environment with requirements.txt installed.
The downloaded checkpoint contains tensors only; torch.load uses weights_only.
"""

import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import urlretrieve

import coremltools as ct
import numpy as np
from PIL import Image
import timm
import torch

REPOSITORY = "BiernyVR/pokemon-classifier-mobilenetv3"
REVISION = "3bf528cf0f6ab8464ea3bac0f70d84886e8dab25"
CHECKPOINT_SHA256 = "58e54044ed3ff747a26717313570e4c0b0f2204e7bdfcef7351d011861b2defe"
ROOT = Path(__file__).resolve().parents[2]


class ImageClassifier(torch.nn.Module):
    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone
        self.register_buffer("mean", torch.tensor([0.485, 0.456, 0.406]).reshape(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor([0.229, 0.224, 0.225]).reshape(1, 3, 1, 1))

    def forward(self, image):
        return self.backbone((image - self.mean) / self.std)


def download(directory, filename):
    target = directory / filename
    if not target.exists():
        urlretrieve(f"https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/{filename}", target)
    return target


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", type=Path, default=Path("/tmp/idex-model-source"))
    parser.add_argument("--verify", action="store_true", help="Compare PyTorch and Core ML using upstream examples and negative images")
    parser.add_argument("--verify-sprites", action="store_true", help="Check the 151 bundled pixel sprites (an in-domain smoke check, not a camera benchmark)")
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    checkpoint = download(args.cache, "pokemon_densenet121_best.pth")
    assert hashlib.sha256(checkpoint.read_bytes()).hexdigest() == CHECKPOINT_SHA256, "Source checkpoint checksum mismatch"
    label_path = download(args.cache, "pokemon_labels.json")
    labels = json.loads(label_path.read_text())
    assert len(labels) == 151 and {p["id"] for p in labels} == set(range(1, 152))
    backbone = timm.create_model("densenet121", pretrained=False, num_classes=len(labels))
    state = torch.load(checkpoint, map_location="cpu", weights_only=True)
    backbone.load_state_dict(state.get("model_state_dict", state))
    wrapper = ImageClassifier(backbone.eval()).eval()
    example = torch.rand(1, 3, 224, 224)
    traced = torch.jit.trace(wrapper, example)
    model = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        compute_precision=ct.precision.FLOAT16,
        inputs=[ct.ImageType(name="image", shape=example.shape, scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name="logits")],
    )
    model.author = "BiernyVR; Core ML conversion for iDex"
    model.short_description = "Offline DenseNet121 image classifier for the 151 Kanto Pokémon."
    model.license = "MIT (upstream repository metadata); Pokémon assets belong to their respective owners."
    model.version = REVISION
    model.user_defined_metadata["source"] = f"https://huggingface.co/{REPOSITORY}/tree/{REVISION}"
    model.user_defined_metadata["checkpoint_sha256"] = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
    model.input_description["image"] = "224 by 224 RGB image, ImageNet normalization is embedded in the model."
    model.output_description["logits"] = "151 unnormalized scores in pokemon_labels.json order; no temperature scaling."
    destination = ROOT / "iDex/Recognition/KantoClassifier.mlpackage"
    model.save(str(destination))
    (destination.parent / "pokemon_labels.json").write_text(json.dumps(labels, indent=2) + "\n")
    print(f"Saved {destination}")
    print(f"Checkpoint SHA256: {model.user_defined_metadata['checkpoint_sha256']}")

    if args.verify:
        cases = []
        for filename, expected in [("sample_pikachu.png", 25), ("sample_charizard.png", 6)]:
            image = Image.open(download(args.cache, filename)).convert("RGBA")
            canvas = Image.new("RGBA", image.size, "white")
            image = Image.alpha_composite(canvas, image).convert("RGB").resize((224, 224), Image.Resampling.BILINEAR)
            cases.append((filename, image, expected))
        cases += [("blank-white", Image.new("RGB", (224, 224), "white"), None),
                  ("blank-black", Image.new("RGB", (224, 224), "black"), None)]
        rng = np.random.default_rng(42)
        cases.append(("random-noise", Image.fromarray(rng.integers(0, 256, (224, 224, 3), dtype=np.uint8)), None))
        records = []
        for name, image, expected in cases:
            tensor = torch.from_numpy(np.array(image).astype(np.float32).transpose(2, 0, 1)[None] / 255)
            with torch.no_grad():
                reference = wrapper(tensor).numpy()[0]
            actual = model.predict({"image": image})["logits"].reshape(-1)
            indices = np.argsort(actual)[::-1]
            probabilities = np.exp(actual - actual.max())
            probabilities /= probabilities.sum()
            margin = float(actual[indices[0]] - actual[indices[1]])
            confidence = float(probabilities[indices[0]])
            accepted = confidence >= 0.25 and margin >= 0.5
            record = {"input": name, "expectedID": expected, "topID": labels[indices[0]]["id"],
                      "confidence": confidence, "logitMargin": margin, "accepted": accepted,
                      "maximumAbsoluteConversionError": float(np.max(np.abs(reference - actual))),
                      "sameTop1AsPyTorch": int(reference.argmax()) == int(actual.argmax())}
            print(json.dumps(record))
            assert record["sameTop1AsPyTorch"]
            if expected is not None:
                assert record["topID"] == expected
            records.append(record)
        (ROOT / "scripts/model/verification.json").write_text(json.dumps(records, indent=2) + "\n")

    if args.verify_sprites:
        records = []
        for identifier in range(1, 152):
            sprite = ROOT / f"iDex/Resources/PokemonSprites.xcassets/pokemon-{identifier:03}.imageset/sprite.png"
            foreground = Image.open(sprite).convert("RGBA")
            background = Image.new("RGBA", foreground.size, "white")
            image = Image.alpha_composite(background, foreground).convert("RGB").resize((224, 224), Image.Resampling.NEAREST)
            logits = model.predict({"image": image})["logits"].reshape(-1)
            indices = np.argsort(logits)[::-1]
            probabilities = np.exp(logits - logits.max())
            probabilities /= probabilities.sum()
            confidence = float(probabilities[indices[0]])
            margin = float(logits[indices[0]] - logits[indices[1]])
            accepted = confidence >= 0.25 and margin >= 0.5
            records.append({"expectedID": identifier, "topID": labels[indices[0]]["id"], "confidence": confidence,
                            "logitMargin": margin, "accepted": accepted})
        summary = {"input": "Bundled Black/White 96px sprites, white alpha composite, nearest-neighbor resize to224",
                   "count": len(records), "correctTop1": sum(r["expectedID"] == r["topID"] for r in records),
                   "accepted": sum(r["accepted"] for r in records),
                   "acceptedWrong": sum(r["accepted"] and r["expectedID"] != r["topID"] for r in records),
                   "records": records}
        (ROOT / "scripts/model/sprite-verification.json").write_text(json.dumps(summary, indent=2) + "\n")
        print({k: v for k, v in summary.items() if k != "records"})


if __name__ == "__main__":
    main()
