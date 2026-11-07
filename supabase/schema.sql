-- =========================================================
-- CMA 第2次レベル 正誤チャレンジ  データベース定義
-- Supabase の SQL Editor に貼って実行（何度実行しても壊れません）
-- 既存の「CMA正誤トレーナー」と同じプロジェクトに入れても衝突しないよう、
-- テーブル名はすべて l2_ で始めています（ログイン情報は共通で使えます）。
-- =========================================================

-- ---------- 会員（ニックネーム・名前・メールアドレス） ----------
create table if not exists public.l2_members (
  id         uuid primary key references auth.users(id) on delete cascade,
  nickname   text not null check (char_length(nickname) between 1 and 30),
  full_name  text not null check (char_length(full_name) between 1 and 60),
  email      text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  role       text not null default 'student' check (role in ('student','teacher')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- 問題 ----------
create table if not exists public.l2_questions (
  id          text primary key,
  subject     text not null,              -- 科目（市場と経済の分析 など）
  unit        text not null,              -- 回（第1回 ○○）
  point_code  text not null,              -- テキストの学習ポイント番号
  point_title text not null,
  level       text not null check (level in ('標準','難問')),
  stem        text not null,
  answer      boolean not null,           -- true=○ false=×
  explanation text not null,
  sort        int not null default 0,
  active      boolean not null default true
);

-- ---------- 受験（1回の挑戦） ----------
create table if not exists public.l2_exams (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.l2_members(id) on delete cascade,
  subject        text,                    -- null = 全科目
  include_hard   boolean not null default false,
  question_count int not null,
  started_at     timestamptz not null default now(),
  finished_at    timestamptz
);

-- ---------- 解答（1問ごとの記録） ----------
create table if not exists public.l2_answers (
  id          bigint generated always as identity primary key,
  exam_id     uuid not null references public.l2_exams(id) on delete cascade,
  user_id     uuid not null references public.l2_members(id) on delete cascade,
  question_id text not null references public.l2_questions(id),
  choice      boolean,                    -- true=○ false=× null=わからない
  is_correct  boolean not null,
  time_ms     int not null check (time_ms >= 0),
  answered_at timestamptz not null default now(),
  unique (exam_id, question_id)
);
-- ---------- 受験ごとに出題した問題（解答できるのはこの問題だけ） ----------
create table if not exists public.l2_exam_questions (
  exam_id     uuid not null references public.l2_exams(id) on delete cascade,
  question_id text not null references public.l2_questions(id),
  position    int  not null,
  primary key (exam_id, question_id)
);

-- 3択（○・×・わからない）対応：わからない = choice が null
alter table public.l2_answers alter column choice drop not null;

create index if not exists l2_answers_user_idx on public.l2_answers(user_id);
create index if not exists l2_answers_question_idx on public.l2_answers(question_id);
create index if not exists l2_exams_user_idx on public.l2_exams(user_id);

-- ---------- 講師かどうか ----------
create or replace function public.l2_is_teacher() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.l2_members where id = auth.uid() and role = 'teacher');
$$;

-- ---------- 受験を始める（正答は返さない） ----------
-- p_subject: null なら全科目。p_include_hard: 難問も出すか。p_limit: 問題数（null なら範囲内の全問）
drop function if exists public.l2_start_exam(text, boolean);
drop function if exists public.l2_start_exam(text, boolean, int);
create or replace function public.l2_start_exam(p_subject text, p_include_hard boolean default true, p_limit int default null)
returns table(exam_id uuid, id text, subject text, unit text, point_code text, point_title text, level text, stem text)
language plpgsql security definer set search_path = public as $$
declare v_exam uuid; v_pool int; v_count int;
begin
  if auth.uid() is null then raise exception 'ログインが必要です'; end if;
  if not exists (select 1 from public.l2_members m where m.id = auth.uid()) then
    raise exception '会員登録が済んでいません';
  end if;
  if p_limit is not null and p_limit < 1 then raise exception '問題数は1問以上にしてください'; end if;
  select count(*) into v_pool from public.l2_questions q
   where q.active and (p_subject is null or q.subject = p_subject) and (coalesce(p_include_hard,false) or q.level = '標準');
  if v_pool = 0 then raise exception '出題できる問題がありません'; end if;
  v_count := least(v_pool, coalesce(p_limit, v_pool));
  insert into public.l2_exams(user_id, subject, include_hard, question_count)
  values (auth.uid(), p_subject, coalesce(p_include_hard,false), v_count) returning l2_exams.id into v_exam;
  -- 範囲内からランダムに v_count 問を選んで記録
  insert into public.l2_exam_questions(exam_id, question_id, position)
  select v_exam, x.id, row_number() over ()
  from (select q.id from public.l2_questions q
        where q.active and (p_subject is null or q.subject = p_subject) and (coalesce(p_include_hard,false) or q.level = '標準')
        order by random() limit v_count) x;
  return query
    select v_exam, q.id, q.subject, q.unit, q.point_code, q.point_title, q.level, q.stem
    from public.l2_exam_questions eq join public.l2_questions q on q.id = eq.question_id
    where eq.exam_id = v_exam order by eq.position;
end $$;

-- ---------- 1問ごとの解答（採点はサーバー側。結果は受験終了まで返さない） ----------
drop function if exists public.l2_submit_answer(uuid, text, boolean, int);
create or replace function public.l2_submit_answer(p_exam uuid, p_question text, p_choice boolean, p_time_ms int)
returns boolean
language plpgsql security definer set search_path = public as $$
declare v_ans boolean;
begin
  if not exists (select 1 from public.l2_exams e where e.id = p_exam and e.user_id = auth.uid() and e.finished_at is null) then
    raise exception 'この受験には解答できません';
  end if;
  select q.answer into v_ans from public.l2_exam_questions eq
   join public.l2_questions q on q.id = eq.question_id
   where eq.exam_id = p_exam and eq.question_id = p_question;
  if not found then raise exception 'この問題はこの受験で出題されていません'; end if;
  insert into public.l2_answers(exam_id, user_id, question_id, choice, is_correct, time_ms)
  values (p_exam, auth.uid(), p_question, p_choice, coalesce(p_choice = v_ans, false), greatest(0, least(p_time_ms, 3600000)))  -- わからない(null)は不正解
  on conflict (exam_id, question_id) do nothing;   -- 二重送信は最初の1回だけ有効
  return true;
end $$;

-- ---------- 受験を終える（ここで初めて正答と解説を返す） ----------
drop function if exists public.l2_finish_exam(uuid);
create or replace function public.l2_finish_exam(p_exam uuid)
returns table(question_id text, choice boolean, is_correct boolean, time_ms int, answer boolean, explanation text)
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.l2_exams e where e.id = p_exam and e.user_id = auth.uid()) then
    raise exception 'この受験の結果は見られません';
  end if;
  update public.l2_exams set finished_at = coalesce(finished_at, now()) where id = p_exam;
  return query
    select a.question_id, a.choice, a.is_correct, a.time_ms, q.answer, q.explanation
    from public.l2_answers a join public.l2_questions q on q.id = a.question_id
    where a.exam_id = p_exam order by a.id;
end $$;

-- ---------- 終了済みの受験の振り返り（自分の分だけ） ----------
drop function if exists public.l2_review(uuid);
create or replace function public.l2_review(p_exam uuid)
returns table(question_id text, choice boolean, is_correct boolean, time_ms int, answer boolean, explanation text)
language sql stable security definer set search_path = public as $$
  select a.question_id, a.choice, a.is_correct, a.time_ms, q.answer, q.explanation
  from public.l2_answers a
  join public.l2_questions q on q.id = a.question_id
  join public.l2_exams e on e.id = a.exam_id
  where a.exam_id = p_exam and e.finished_at is not null
    and (e.user_id = auth.uid() or public.l2_is_teacher())
  order by a.id;
$$;

-- ---------- 問題の一覧（正答なし。振り返り・分析画面の表示用） ----------
drop function if exists public.l2_question_list();
create or replace function public.l2_question_list()
returns table(id text, subject text, unit text, point_code text, point_title text, level text, stem text, sort int)
language sql stable security definer set search_path = public as $$
  select q.id, q.subject, q.unit, q.point_code, q.point_title, q.level, q.stem, q.sort
  from public.l2_questions q where auth.uid() is not null order by q.sort;
$$;

-- ---------- みんなの成績（集計値のみ。時間は中央値、5分超は除外） ----------
drop function if exists public.l2_question_stats();
create or replace function public.l2_question_stats()
returns table(question_id text, n bigint, accuracy numeric, median_ms numeric, unsure_rate numeric)
language sql stable security definer set search_path = public as $$
  select a.question_id, count(*), round(avg(a.is_correct::int)::numeric, 4),
         round((percentile_cont(0.5) within group (order by a.time_ms) filter (where a.time_ms <= 300000))::numeric),
         round(avg((a.choice is null)::int)::numeric, 4)
  from public.l2_answers a where auth.uid() is not null group by a.question_id;
$$;

-- ---------- 行レベルセキュリティ ----------
alter table public.l2_members   enable row level security;
alter table public.l2_questions enable row level security;
alter table public.l2_exams     enable row level security;
alter table public.l2_answers   enable row level security;
alter table public.l2_exam_questions enable row level security;

drop policy if exists "l2_members: 本人か講師が読める" on public.l2_members;
create policy "l2_members: 本人か講師が読める" on public.l2_members for select
  using (id = auth.uid() or public.l2_is_teacher());
drop policy if exists "l2_members: 本人が登録" on public.l2_members;
create policy "l2_members: 本人が登録" on public.l2_members for insert
  with check (id = auth.uid() and role = 'student');
drop policy if exists "l2_members: 本人が変更" on public.l2_members;
create policy "l2_members: 本人が変更" on public.l2_members for update
  using (id = auth.uid()) with check (id = auth.uid());
-- 役割(role)は本人が変えられない：更新できる列を限定
revoke update on public.l2_members from anon, authenticated;
grant update (nickname, full_name, email, updated_at) on public.l2_members to authenticated;

drop policy if exists "l2_questions: 講師が全操作" on public.l2_questions;
create policy "l2_questions: 講師が全操作" on public.l2_questions for all
  using (public.l2_is_teacher()) with check (public.l2_is_teacher());

-- 受験と解答は関数経由でのみ書き込む（直接の insert/update ポリシーは作らない）
drop policy if exists "l2_exams: 本人か講師が読める" on public.l2_exams;
create policy "l2_exams: 本人か講師が読める" on public.l2_exams for select
  using (user_id = auth.uid() or public.l2_is_teacher());
drop policy if exists "l2_exam_questions: 本人か講師が読める" on public.l2_exam_questions;
create policy "l2_exam_questions: 本人か講師が読める" on public.l2_exam_questions for select
  using (exists (select 1 from public.l2_exams e where e.id = exam_id and e.user_id = auth.uid()) or public.l2_is_teacher());
drop policy if exists "l2_answers: 本人か講師が読める" on public.l2_answers;
-- 本人は「終了した受験」の解答だけ読める（受験中に正誤を盗み見できないように）
create policy "l2_answers: 本人か講師が読める" on public.l2_answers for select
  using ((user_id = auth.uid() and exists (select 1 from public.l2_exams e where e.id = exam_id and e.finished_at is not null))
         or public.l2_is_teacher());

-- ---------- 関数の実行権限 ----------
revoke execute on function public.l2_start_exam(text, boolean, int)         from anon, public;
revoke execute on function public.l2_submit_answer(uuid, text, boolean, int) from anon, public;
revoke execute on function public.l2_finish_exam(uuid)                      from anon, public;
revoke execute on function public.l2_review(uuid)                           from anon, public;
revoke execute on function public.l2_question_list()                        from anon, public;
revoke execute on function public.l2_question_stats()                       from anon, public;
grant  execute on function public.l2_start_exam(text, boolean, int)         to authenticated;
grant  execute on function public.l2_submit_answer(uuid, text, boolean, int) to authenticated;
grant  execute on function public.l2_finish_exam(uuid)                      to authenticated;
grant  execute on function public.l2_review(uuid)                           to authenticated;
grant  execute on function public.l2_question_list()                        to authenticated;
grant  execute on function public.l2_question_stats()                       to authenticated;

-- ---------- 変更をすぐAPIに反映させる（関数が見つからないエラーの防止） ----------
notify pgrst, 'reload schema';
