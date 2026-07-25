"""
Dataset Organizer for ISL Training Data
========================================
Sorts video and .npy dataset files into categorized folders based on filename.

Rules:
  - Single-word files  → folder named after the word (UPPERCASE canonical name)
    e.g. Hello.mp4, hello.mp4, HELLO.mp4  → all go into HELLO/
    Original filenames are PRESERVED so the model trains on case variations.

  - Sentence files (filename has spaces / multiple words) → _sentences/ folder
    e.g. "where are you going.mp4" → _sentences/

Usage:
    python organize_dataset.py <source_folder>                   # copy mode (safe)
    python organize_dataset.py <source_folder> --move            # move mode
    python organize_dataset.py <source_folder> --dry-run         # preview only
    python organize_dataset.py <source_folder> -o <output_dir>   # custom output

Examples:
    python organize_dataset.py "C:/Users/me/Downloads/new_signs"
    python organize_dataset.py ./my_dataset --move --dry-run
"""

import os
import sys
import shutil
import argparse
from collections import defaultdict

# ---------------------------------------------------------------------------
# Supported file extensions
# ---------------------------------------------------------------------------
SUPPORTED_EXTENSIONS = {".mp4", ".avi", ".mov", ".npy", ".webm", ".mkv"}

# Folder name for sentence-type files
SENTENCES_FOLDER = "_sentences"


# ---------------------------------------------------------------------------
# Classification helpers
# ---------------------------------------------------------------------------
def get_name_without_extension(filename: str) -> str:
    """Return the filename without its extension.

    >>> get_name_without_extension("Hello.mp4")
    'Hello'
    >>> get_name_without_extension("where are you going.mp4")
    'where are you going'
    """
    return os.path.splitext(filename)[0]


def is_sentence(name: str) -> bool:
    """A file is a 'sentence' if its stem (name without extension) contains
    at least one space, indicating multiple words.

    >>> is_sentence("Hello")
    False
    >>> is_sentence("where are you going")
    True
    """
    return " " in name.strip()


def get_canonical_folder(name: str) -> str:
    """Return the canonical (UPPERCASE) folder name for a single-word file.

    >>> get_canonical_folder("hello")
    'HELLO'
    >>> get_canonical_folder("Go")
    'GO'
    """
    return name.strip().upper()


def make_unique_path(dest_path: str) -> str:
    """If dest_path already exists, append _1, _2, … until unique.

    >>> # If HELLO/hello.mp4 already exists:
    >>> make_unique_path("organized/HELLO/hello.mp4")
    'organized/HELLO/hello_1.mp4'
    """
    if not os.path.exists(dest_path):
        return dest_path

    base, ext = os.path.splitext(dest_path)
    counter = 1
    while os.path.exists(f"{base}_{counter}{ext}"):
        counter += 1
    return f"{base}_{counter}{ext}"


# ---------------------------------------------------------------------------
# Core organizer
# ---------------------------------------------------------------------------

# Folder names to always skip (case-insensitive) when scanning sources
SKIP_FOLDER_NAMES = {"organized_dataset", "dataset_inbox", ".git", "__pycache__", "venv", ".venv"}


def scan_source(source_dir: str, output_dir: str = None) -> list:
    """Walk through source_dir and collect all supported files.

    Returns a list of (absolute_filepath, subfolder_label_or_None).
    - If the file is directly in source_dir root -> label is None (classify by filename)
    - If the file is inside a direct subdirectory of source_dir -> label is that
      subdirectory's name (used as the category regardless of filename)
    - Deeper nesting uses the first-level subdirectory name as the label.

    Skips the output_dir entirely and any folders named in SKIP_FOLDER_NAMES
    to prevent recursive self-processing.
    """
    source_dir = os.path.abspath(source_dir)
    output_dir = os.path.abspath(output_dir) if output_dir else None

    collected = []
    for root, dirs, files in os.walk(source_dir):
        abs_root = os.path.abspath(root)

        # Skip the output directory itself (and anything inside it)
        if output_dir and (abs_root == output_dir or abs_root.startswith(output_dir + os.sep)):
            dirs.clear()
            continue

        # Skip known system/tool folders at any level
        rel = os.path.relpath(abs_root, source_dir)
        top_folder = rel.split(os.sep)[0] if rel != "." else None
        if top_folder and top_folder.lower() in SKIP_FOLDER_NAMES:
            dirs.clear()
            continue

        # Prune dirs in-place so os.walk doesn't descend into skipped folders
        dirs[:] = [d for d in dirs if d.lower() not in SKIP_FOLDER_NAMES]
        if output_dir:
            dirs[:] = [d for d in dirs
                       if os.path.abspath(os.path.join(root, d)) != output_dir]

        # Determine the first-level subfolder label relative to source_dir
        if rel == ".":
            subfolder_label = None  # file is directly in source root -> classify by filename
        else:
            subfolder_label = rel.split(os.sep)[0]  # top-level subfolder name is the label

        for f in files:
            ext = os.path.splitext(f)[1].lower()
            if ext in SUPPORTED_EXTENSIONS:
                collected.append((os.path.join(root, f), subfolder_label))
    return collected


def organize(source_dir: str, output_dir: str, move: bool = False,
             dry_run: bool = False) -> dict:
    """Organize files from source_dir into output_dir.

    Returns a summary dict with stats.
    """
    source_dir = os.path.abspath(source_dir)
    output_dir = os.path.abspath(output_dir)

    if not os.path.isdir(source_dir):
        print(f"[ERROR] Source folder does not exist: {source_dir}")
        sys.exit(1)

    file_entries = scan_source(source_dir, output_dir)
    if not file_entries:
        print(f"[WARNING] No supported files found in: {source_dir}")
        print(f"  Supported extensions: {', '.join(sorted(SUPPORTED_EXTENSIONS))}")
        return {"total": 0, "words": 0, "sentences": 0, "folders": set()}

    # ---- Classify every file ----
    plan = []  # list of (src_path, dest_folder, dest_filename)
    for filepath, subfolder_label in file_entries:
        filename = os.path.basename(filepath)

        if subfolder_label is not None:
            # File lives inside a named subfolder — use that folder name as label.
            # Normalize to UPPERCASE; treat multi-word folder names as sentences.
            if is_sentence(subfolder_label):
                dest_folder = SENTENCES_FOLDER
            else:
                dest_folder = get_canonical_folder(subfolder_label)
        else:
            # File is in the root of source_dir — classify by filename.
            stem = get_name_without_extension(filename)
            if is_sentence(stem):
                dest_folder = SENTENCES_FOLDER
            else:
                dest_folder = get_canonical_folder(stem)

        plan.append((filepath, dest_folder, filename))

    # ---- Build summary for display ----
    folder_counts = defaultdict(list)
    for src, folder, fname in plan:
        folder_counts[folder].append(fname)

    # ---- Print plan ----
    action = "MOVE" if move else "COPY"
    mode_label = " [DRY RUN]" if dry_run else ""
    print()
    print("=" * 65)
    print(f"  Dataset Organizer - {action} Mode{mode_label}")
    print("=" * 65)
    print(f"  Source : {source_dir}")
    print(f"  Output : {output_dir}")
    print(f"  Files  : {len(file_entries)} found")
    print("-" * 65)

    # Sort folders: word folders alphabetically, _sentences last
    sorted_folders = sorted(folder_counts.keys(),
                            key=lambda f: (f == SENTENCES_FOLDER, f))

    word_count = 0
    sentence_count = 0

    for folder in sorted_folders:
        file_list = folder_counts[folder]
        if folder == SENTENCES_FOLDER:
            sentence_count = len(file_list)
            label = f"  [SENTENCE] {folder}/"
        else:
            word_count += len(file_list)
            label = f"  [WORD] {folder}/"

        print(label)
        for fname in sorted(file_list):
            print(f"      |-- {fname}")
        print()

    print("-" * 65)
    print(f"  Summary: {word_count} word files -> {len(sorted_folders) - (1 if sentence_count else 0)} folders")
    if sentence_count:
        print(f"           {sentence_count} sentence files -> {SENTENCES_FOLDER}/")
    print(f"  Total  : {len(file_entries)} files")
    print("=" * 65)

    # ---- Execute ----
    if dry_run:
        print("\n  [OK] Dry run complete - no files were changed.\n")
        return {
            "total": len(file_entries),
            "words": word_count,
            "sentences": sentence_count,
            "folders": set(f for f in sorted_folders if f != SENTENCES_FOLDER),
        }

    transferred = 0
    for src, folder, fname in plan:
        dest_dir = os.path.join(output_dir, folder)
        os.makedirs(dest_dir, exist_ok=True)

        dest_path = os.path.join(dest_dir, fname)
        dest_path = make_unique_path(dest_path)

        if move:
            shutil.move(src, dest_path)
        else:
            shutil.copy2(src, dest_path)

        transferred += 1

    action_past = "moved" if move else "copied"
    print(f"\n  [OK] Done! {transferred} files {action_past} to {output_dir}\n")

    return {
        "total": len(file_entries),
        "words": word_count,
        "sentences": sentence_count,
        "folders": set(f for f in sorted_folders if f != SENTENCES_FOLDER),
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Organize ISL dataset files into categorized folders.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
INBOX MODE (recommended - paste and run):
  1. Paste your dataset folders into:  backend/dataset_inbox/
  2. Run with no arguments:            python organize_dataset.py
  3. All files land in:                backend/organized_dataset/

MANUAL MODE:
  python organize_dataset.py "C:/path/to/my_dataset"
  python organize_dataset.py "C:/path/folder1" "C:/path/folder2"
  python organize_dataset.py "C:/path/to/folder" --move
  python organize_dataset.py "C:/path/to/folder" --dry-run
  python organize_dataset.py "C:/path/to/folder" -o "C:/path/to/output"
        """,
    )
    parser.add_argument(
        "sources",
        nargs="*",
        help="One or more source folders to organize. "
             "If omitted, all folders inside dataset_inbox/ are processed automatically.",
    )
    parser.add_argument(
        "-o", "--output",
        default=None,
        help="Output directory (default: backend/organized_dataset/).",
    )
    parser.add_argument(
        "--move",
        action="store_true",
        help="Move files instead of copying (destructive).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview the organization without touching any files.",
    )

    args = parser.parse_args()

    # Paths relative to this script (backend/)
    backend_dir = os.path.dirname(os.path.abspath(__file__))
    inbox_dir   = os.path.join(backend_dir, "dataset_inbox")
    output_dir  = args.output or os.path.join(backend_dir, "organized_dataset")

    # ---- Determine source folders ----
    if args.sources:
        # Explicit paths on the command line
        source_dirs = [os.path.abspath(s) for s in args.sources]
    else:
        # INBOX MODE: auto-scan dataset_inbox/ for all pasted folders
        if not os.path.isdir(inbox_dir):
            print(f"[ERROR] No source given and inbox not found: {inbox_dir}")
            print(f"        Create it, paste your dataset folders inside, then re-run.")
            sys.exit(1)

        children = sorted(os.listdir(inbox_dir))
        source_dirs = [
            os.path.join(inbox_dir, c)
            for c in children
            if os.path.isdir(os.path.join(inbox_dir, c))
        ]

        # Loose files directly in inbox -> treat inbox itself as a source too
        loose = [
            c for c in children
            if os.path.isfile(os.path.join(inbox_dir, c))
            and os.path.splitext(c)[1].lower() in SUPPORTED_EXTENSIONS
        ]
        if loose:
            source_dirs = [inbox_dir] + [d for d in source_dirs if d != inbox_dir]

        if not source_dirs:
            print("[WARNING] dataset_inbox/ is empty.")
            print(f"  Paste your dataset folders into: {inbox_dir}")
            sys.exit(0)

        print(f"[INBOX] Found {len(source_dirs)} dataset source(s) to process:")
        for s in source_dirs:
            print(f"  -> {os.path.basename(s)}")
        print()

    # ---- Process each source, merging into the same output dir ----
    total = {"total": 0, "words": 0, "sentences": 0, "folders": set()}
    for source in source_dirs:
        stats = organize(source, output_dir, move=args.move, dry_run=args.dry_run)
        total["total"]     += stats.get("total", 0)
        total["words"]     += stats.get("words", 0)
        total["sentences"] += stats.get("sentences", 0)
        total["folders"]   |= stats.get("folders", set())

    if len(source_dirs) > 1:
        print("=" * 65)
        print(f"  GRAND TOTAL : {total['total']} files from {len(source_dirs)} sources")
        print(f"  Word files  : {total['words']} -> {len(total['folders'])} folders")
        print(f"  Sentences   : {total['sentences']} -> _sentences/")
        print(f"  Output      : {output_dir}")
        print("=" * 65)


if __name__ == "__main__":
    main()
