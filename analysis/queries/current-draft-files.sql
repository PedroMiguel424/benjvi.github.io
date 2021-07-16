create temporary view latest_commit as
select id
from blog_repo_commits 
order by author_when desc 
limit 1;

create temporary view draft_post_details as
with first_commit_for_file as (
  select 
    file,
    min(author_when) as first_commit_time
  from blog_repo_commits
  left join blog_repo_stats
  on blog_repo_commits.id = blog_repo_stats.commit_id
  group by 1
)
select
  commit_id,
  name,
  first_commit_time,
  now() - first_commit_time as draft_age
from blog_repo_files
join first_commit_for_file
on first_commit_for_file.file = blog_repo_files.name
where blog_repo_files.name ilike '_drafts/%';

select *
from draft_post_details
join latest_commit
on draft_post_details.commit_id=latest_commit.id;

select
 count(*),
 avg(draft_age)
from draft_post_details
join latest_commit 
on draft_post_details.commit_id=latest_commit.id;

select
  commit_id,
  author_when,
  count(*),
  avg(draft_age)
from draft_post_details
join blog_repo_commits
on commit_id = blog_repo_commits.id
group by commit_id,author_when
order by author_when;
