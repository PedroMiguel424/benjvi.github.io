-- amount of time spent editing before publishing
select 
  p.title,
  p.first - f.time
from published_edit p
left join first_draft_edit f
on p.title=f.title
where f.time is not null; 


