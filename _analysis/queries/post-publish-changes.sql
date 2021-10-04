-- number of changes made to an already published post
select
  p.filepath,
  count(*)-1 as "number of post-publish edits",
  min(blog_repo_commits.author_when) as "publish_time",
  max(blog_repo_commits.author_when)
from published_posts p
left join blog_repo_stats
on p.filepath=blog_repo_stats.file
left join blog_repo_commits
on blog_repo_stats.commit_id=blog_repo_commits.id
group by p.filepath;


