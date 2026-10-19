"""Reads the text on a receipt photo with RapidOCR (PaddleOCR models, run offline).

Usage: read_receipt.py IMAGE_PATH
Prints a JSON array of {"text": str, "box": [[x, y] x4], "score": float}, one per
detected text line, with the box corners in reading order (top-left first).

RECEIPT_OCR_THREADS caps onnxruntime's threads; by default it uses every core it can
see, which in a container can be far more than the CPU quota.
"""

import json
import logging
import os
import sys

from rapidocr import RapidOCR


def main(path):
    logging.disable(logging.CRITICAL)
    threads = int(os.environ.get("RECEIPT_OCR_THREADS", "0"))
    params = {"EngineConfig.onnxruntime.intra_op_num_threads": threads} if threads > 0 else None
    result = RapidOCR(params=params)(path)
    lines = []
    if result.boxes is not None:
        for box, text, score in zip(result.boxes, result.txts, result.scores):
            lines.append({"text": text, "box": [[float(x), float(y)] for x, y in box], "score": float(score)})
    json.dump(lines, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: read_receipt.py IMAGE_PATH")
    main(sys.argv[1])
