# 問題データ（tools/questions.py）から supabase/seed.sql と tools/questions.json を作る
# 使い方: python3 tools/build_seed.py
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from questions import Q, UNITS, POINTS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def lit(s): return "'" + str(s).replace("'", "''") + "'"

rows, js = [], []
for i, (u, pc, lv, stem, ans, exp) in enumerate(Q, 1):
    subj, unit = UNITS[u]
    qid = f"{u}-{i:03d}"
    rows.append(f"({lit(qid)},{lit(subj)},{lit(unit)},{lit(pc)},{lit(POINTS[pc])},{lit(lv)},{lit(stem)},{'true' if ans else 'false'},{lit(exp)},{i})")
    js.append(dict(id=qid, subject=subj, unit=unit, point_code=pc, point_title=POINTS[pc], level=lv, stem=stem, answer=ans, explanation=exp, sort=i))

sql = ("-- CMA 第2次レベル オリジナル正誤問題（" + str(len(Q)) + "問）\n"
       "-- tools/questions.py から自動生成。直接編集せず questions.py を直して python3 tools/build_seed.py を実行\n"
       "insert into public.l2_questions (id, subject, unit, point_code, point_title, level, stem, answer, explanation, sort) values\n"
       + ",\n".join(rows) +
       "\non conflict (id) do update set subject=excluded.subject, unit=excluded.unit, point_code=excluded.point_code,\n"
       "  point_title=excluded.point_title, level=excluded.level, stem=excluded.stem, answer=excluded.answer,\n"
       "  explanation=excluded.explanation, sort=excluded.sort, active=true;\n")
open(os.path.join(ROOT, "supabase", "seed.sql"), "w", encoding="utf-8").write(sql)
json.dump(js, open(os.path.join(ROOT, "tools", "questions.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(f"{len(Q)}問を書き出しました")
