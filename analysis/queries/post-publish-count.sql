-- number of posts published this year
-- and previous years
-- decided that I don't really care how long each post is, just how many posts I publish
-- maybe average number of words is interesting, but should be evaluated post-by-posts
select 
  date_trunc('year', first),
  count(distinct file)
from published_edit
group by 1
order by 1;


