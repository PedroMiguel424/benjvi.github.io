-- number of commits on the posts each year
select 
  date_trunc('month', author_when),
  count(*)
from (
  select *
  from published_post_commits
  union
  select *
  from draft_post_commits
) as post_commits
group by 1
order by 1 desc;

