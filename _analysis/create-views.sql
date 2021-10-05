create or replace view draft_posts as
select distinct
  regexp_replace(file, '^_drafts\/([0-9]{4}-[0-9]{2}-[0-9]{2}-)?', '') as title,
  file as filepath
from blog_repo_stats
where file like '_drafts/%';

create or replace view published_posts as
select distinct 
  regexp_replace(file, '^_posts\/([0-9]{4}-[0-9]{2}-[0-9]{2}-)?', '') as title,
  file as filepath
from blog_repo_stats
where file like '_posts/%';


create or replace view posts_with_drafts as
select 
  published_posts.filepath as published_filepath,
  published_posts.title as title,
  draft_posts.filepath as draft_filepath
from published_posts
left join draft_posts
on published_posts.title = draft_posts.title;

-- following views all relate to previous edits of now-published posts
create or replace view published_edit as
  select 
    blog_repo_stats.file as file,
    posts_with_drafts.title as title,
    max(blog_repo_commits.author_when) as last,
    min(blog_repo_commits.author_when) as first
  from blog_repo_commits
  left join blog_repo_stats
  on blog_repo_stats.commit_id=blog_repo_commits.id
  join posts_with_drafts
  on posts_with_drafts.published_filepath=blog_repo_stats.file
  group by 1,2;

create or replace view first_draft_edit as
  select
    blog_repo_stats.file as file,
    posts_with_drafts.title as title,
    min(blog_repo_commits.author_when) as time
  from blog_repo_commits
  left join blog_repo_stats
  on blog_repo_stats.commit_id=blog_repo_commits.id
  join posts_with_drafts
  on posts_with_drafts.draft_filepath=blog_repo_stats.file 
  group by 1,2;

create or replace view first_published_edit as
  select
    blog_repo_stats.file as file,
    posts_with_drafts.title as title,
    min(blog_repo_commits.author_when) as time
  from blog_repo_commits
  left join blog_repo_stats
  on blog_repo_stats.commit_id=blog_repo_commits.id
  join posts_with_drafts
  on posts_with_drafts.published_filepath=blog_repo_stats.file 
  group by 1,2;

create or replace view first_edit as
  select
    posts_with_drafts.title as title,
    min(blog_repo_commits.author_when) as time
  from blog_repo_commits
  left join blog_repo_stats
  on blog_repo_stats.commit_id=blog_repo_commits.id
  join posts_with_drafts
  on (
    posts_with_drafts.draft_filepath=blog_repo_stats.file 
    or posts_with_drafts.published_filepath=blog_repo_stats.file 
  )
  group by 1;
-- end section (edits of now-published posts)

create or replace view blog_deploy_commits as 
select distinct 
  file,id,author_when,message
from commits
left join stats
on stats.commit_id = commits.id
where file ilike 'sync/prod/blog/k8s-blog/%.yml';

create or replace view published_post_commits as 
select distinct
  file,id,author_when,message
from blog_repo_commits
left join blog_repo_stats
on blog_repo_stats.commit_id = blog_repo_commits.id
where file ilike '_posts/%';

create or replace view draft_post_commits as 
select distinct
  file,id,author_when,message
from blog_repo_commits
left join blog_repo_stats
on blog_repo_stats.commit_id = blog_repo_commits.id
where file ilike '_drafts/%';

-- time taken to deploy a post once its published
create or replace view post_publish_to_deploy as
select 
  published_post_commits.file as post_filepath,
  published_post_commits.author_when as publish_commit_time,
  blog_deploy_commits.author_when as deploy_commit_time,
  extract( epoch from (blog_deploy_commits.author_when - published_post_commits.author_when))/60 as minutes_between_publish_and_deploy
from published_post_commits
left join blog_deploy_commits
on blog_deploy_commits.author_when = (
   select 
     min(author_when)
   from blog_deploy_commits
   where blog_deploy_commits.author_when > published_post_commits.author_when
)
-- only interested in commits after I started hosting the blog on k8s
where published_post_commits.author_when > '2021/05/03 11:00:00';

create or replace view latest_commit as
select id
from blog_repo_commits 
order by author_when desc 
limit 1;

create or replace view draft_post_details as
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
  blog_repo_stats.file as "name",
  first_commit_time,
  now() - first_commit_time as draft_age
from blog_repo_stats
join first_commit_for_file
on first_commit_for_file.file = blog_repo_stats.file
where blog_repo_stats.file ilike '_drafts/%';

