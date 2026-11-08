-- Run in the connected Supabase project's SQL editor after reviewing.
-- This updates the existing event without touching questions, teams, scores or photos.
update public.events
set title = 'Claire''s Birthday Sock Hop',
    description = 'A Celebration of Oldies But Goodies! Rock around the clock with music, movies, history, and pop culture trivia from the fabulous ''50s, plus a few birthday-girl surprises.'
where id = 'birthday-main';

-- Verify the event copy:
select id, title, description from public.events where id = 'birthday-main';
