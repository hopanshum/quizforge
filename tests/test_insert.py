"""Local fork: #insert[...] puts free content between parts or after the last
part, in both modes, without being shuffled or counted as a question."""

import json
import shutil
import subprocess

import pytest

from conftest import ROOT

FIX = "tests/fixtures/markup-insert.typ"


def run(*args):
    proc = subprocess.run(["typst", *args, "--root", str(ROOT)], cwd=ROOT,
                          capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr
    return proc


@pytest.mark.parametrize("set_id", ["A", "B"])
def test_insert_is_not_a_question(set_id):
    key = json.loads(run("query", FIX, "<answerkey>", "--field", "value", "--one",
                         "--input", f"set={set_id}").stdout)
    assert [len(s["questions"]) for s in key["sections"]] == [2, 1]
    assert key["total"] == 3


@pytest.mark.skipif(shutil.which("pdftotext") is None, reason="needs pdftotext")
@pytest.mark.parametrize("mode", ["exam", "key"])
def test_insert_position(mode, tmp_path):
    pdf = tmp_path / "o.pdf"
    proc = run("compile", FIX, str(pdf), "--input", f"mode={mode}")
    assert "warning" not in proc.stderr
    txt = subprocess.run(["pdftotext", str(pdf), "-"], capture_output=True, text=True).stdout
    order = [txt.index(s) for s in
             ("Part One", "INTERLUDE-TEXT", "Part Two", "End of paper", "APPENDIX-TEXT")]
    assert order == sorted(order)
