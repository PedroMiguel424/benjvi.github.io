-- total amount of time between first and last change
select
  p.title,
  p.last - f.time
from published_edit p
left join first_edit f
on p.title=f.title
where f.time is not null;


