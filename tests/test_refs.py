"""Local fork: <label> on a question or subquestion, referenced with @name.

A reference must point at the question's number in *each set* (questions are
shuffled), and adding labels must not change question ids (labels carry no
text, so ids hashed from the text stay put)."""

import json
import shutil
import subprocess

import pytest

from conftest import ROOT

FIX = "tests/fixtures/markup-refs.typ"
NOLAB = "tests/fixtures/markup-refs-nolabels.typ"


def query(path, selector, field, set_id):
    cmd = ["typst", "query", path, selector, "--field", field, "--root", str(ROOT),
           "--input", f"set={set_id}"]
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout)


def answerkey(path, set_id):
    return query(path, "<answerkey>", "value", set_id)[0]


def qno_of_marks(key, marks):
    (q,) = [q for s in key["sections"] for q in s["questions"] if q["marks"] == marks]
    return q["qno"]


@pytest.mark.parametrize("set_id", ["A", "B"])
def test_anchor_follows_shuffle(set_id):
    key = answerkey(FIX, set_id)
    demand_qno = qno_of_marks(key, 3)  # the only 3-mark question
    assert query(FIX, "<demand>", "body", set_id) == [
        {"func": "metadata", "value": {"qno": demand_qno, "part": None}}]
    assert query(FIX, "<price>", "body", set_id)[0]["value"] == {"qno": demand_qno, "part": "a"}
    assert query(FIX, "<cs>", "body", set_id)[0]["value"] == {"qno": demand_qno, "part": "b"}


def test_order_differs_between_sets():
    # otherwise test_anchor_follows_shuffle proves nothing about shuffling
    orders = {s: [q["id"] for sec in answerkey(FIX, s)["sections"] for q in sec["questions"]]
              for s in ("A", "B")}
    assert orders["A"] != orders["B"]


@pytest.mark.parametrize("set_id", ["A", "B"])
def test_labels_do_not_change_ids(set_id):
    # the 3-mark question carries labels on its stem and parts; the 1-mark one
    # has none (the 2-mark one's text differs: @refs vs written-out numbers)
    def ids(p):
        return {q["marks"]: q["id"] for s in answerkey(p, set_id)["sections"]
                for q in s["questions"]}
    a, b = ids(FIX), ids(NOLAB)
    assert a[3] == b[3]
    assert a[1] == b[1]


@pytest.mark.skipif(shutil.which("pdftotext") is None, reason="needs pdftotext")
@pytest.mark.parametrize("set_id", ["A", "B"])
@pytest.mark.parametrize("mode", ["exam", "key"])
def test_reference_text(set_id, mode, tmp_path):
    pdf = tmp_path / "out.pdf"
    proc = subprocess.run(
        ["typst", "compile", FIX, str(pdf), "--root", str(ROOT),
         "--input", f"set={set_id}", "--input", f"mode={mode}"],
        cwd=ROOT, capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr
    assert "warning" not in proc.stderr
    txt = " ".join(subprocess.run(["pdftotext", str(pdf), "-"], capture_output=True,
                                  text=True).stdout.split())
    n = qno_of_marks(answerkey(FIX, set_id), 3)
    # inside its own question a part is "(a)"; elsewhere it is "Q<n>(a)"
    assert "Using (a), compute" in txt
    assert f"Use your answers to Q{n}(a) and Q{n}." in txt
    if mode == "key":
        assert "used again in (b)" in txt
        assert f"See Q{n}(b)." in txt
