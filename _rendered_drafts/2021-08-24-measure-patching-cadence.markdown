---
layout: post
title: "Measuring Patching Cadence on Kubernetes with `askgit`"
categories: [technology]
---

![patching dashboard](img/full-patching-dashboard.png)

I run a Kubernetes cluster at home, running on Raspberry Pi's, which I use to run various services. To make this a useful platform, I run a bunch of supporting third party services, things such as:
- Prometheus & Grafana
- Gatekeeper
- MetalLB
- Weave Network Plugin

When you run services you also have to worry about keeping them up-to-date, for a few reasons:

- As time passes, more and more CVEs are found for old software, and with that the risk of being hacked multiplies. This is particularly risky for systems accessible from the public internet, as is the case for some services that I run.
- Even software that is not vulnerable may also become problematic. If other (vulnerable) components are upgraded around an unchanged piece of software, newer versions may choose to drop compatibility with older APIs, and integrations may break.
- Finally, most software is broken on some level. You often run into bugs and feature gaps, where your use case is different from what the authors expected. Many (or at least some) of these issues are fixed in software updates.

For these reasons, it's important not just to be able to install the software, but also to be able to easily & reliably update it too.

# Upgradeable

Unfortunately, designing your system for upgrades requires more care than just installing a package. You should:
- Keep track of the current state of your infrastructure using Infrastructure as Code, aka package manifest YAML files checked-in to git
- Keep track of where to pull the package from, and possibly an upgrade process too, using something like [Vendir](https://carvel.dev/vendir/docs/latest/).
- Keep track of any customizations you made to a package, and define a repeatable process for applying them
- Define some process for keeping secrets in-sync with the deployed packages
- If you have multiple environments, define a process for rolling out updates sequentially to those environments, and giving the appropriate environment-specific parameters

None of this is easy, and each aspect requires some engineering effort. And when things get more complex, its easy to lose sight of the big picture. Its important to make sure we aren't just cargo-culting practices, and to know our efforts are actually achieving good outcomes. Therefore, we should *identify the metrics we want to improve*, and *measure their trends*.

# Measurement

To choose appropriate metrics, we can look to the ideas in the world of Continuous Delivery. Even though this we aren't developing the software ourselves, a lot of the same ideas are important.

In particular, the top level metrics for teams looking to improve performance (the DORA metrics) are very relevant:
- (Increasing) Deployment Frequency
- (Decreasing) Lead Time for Delivery
- (Decreasing) Mean Time To Recovery (MTTR) 
- (Increasing) Proportion of successful releases

Importantly, these are very precise things that we can (in principle) quantitatively measure. At a high level, you would calculate them something like this:
- *Frequency* = `(number of deployments) / (time period)`
- *Lead time* = `(time of production deployment) - (time of associated code commit)`
- *MTTR* = `(time an incident began) - (time an incident ended)`
- *Change Failure Rate* = `(number of releases triggering incidents) / (number of releases) = 1 - proportion of successful releases `

In broad terms, these four metrics relate to counting and gathering timings over deployment events (Deployment Frequency & Lead Time), and then relating that to counts and timings of service incidents (giving MTTR and Change Failure Rate).

If you are using a GitOps repo, all the information needed to measure *Deployment Frequency* and *Lead Time* can be extracted entirely from the Git history. This is what we're going to dig into in subsequent sections of this post. To help with that, we'll use `askgit`. It's a CLI tool that allows us to query metadata associated with the commits in a git repo via SQL. 

# Introducing [`askgit`](https://github.com/askgitdev/askgit)

Exposing the data in your git history means you can ask all different sorts of questions. There is a `commits` table so we can just ask for a list of all the commits, similar to what you would get with `git log`:

```
askgit 'select * from commits'
```

We can also augment this with information about what files changed in each commit, from the `stats` table. This allows us to identify commits containing a vendored package update, by the fact that the files changed include vendored package files (in the `packages/vendored` directory): 

```
askgit "select * from commits left join stats on stats.commit_id = commits.id where file like 'packages/vendored/'" 
```

Similarly, we will get prod deployment events when commits include changed files representing the desired state of prod (those under `sync/prod`):

```
askgit "select * from commits left join stats on stats.commit_id = commits.id  where file like 'sync/prod'"
```

This does require the presence of a Gitops tool like ArgoCD to make sure that updates made to a Git repo are reflected as actual deployment events. 

The other very handy feature of `askgit` is the ability to export data to an SQLite database, with a command like:

```
askgit export monitoring/askgit-commits-stats-db.sqlite3 -e commits -e "select * from commits" -e stats -e "select * from stats('', commits.hash)" 
```
SQLite is very well supported by many tools, so once you have an SQLite database there are lots of tools you can use to further process the data. I used `pgloader` (with the [appropriate config](https://github.com/benjvi/measuring-patching-cadence/blob/main/askgit-sqlite-to-postgres.txt)) to load the data into Postgres so we will be able to query it from Grafana. This config will need to be customized with the details of your postgres server. Then, to load the data based on that config you need to run:

```
pgloader askgit-sqlite-to-postgres.txt
```

I also created [a Kubernetes `CronJob`](https://github.com/benjvi/measuring-patching-cadence/blob/main/cronjob.yml) you can run to continually load the latest data from your repo (make sure you update it to point at your repo!).

# Package Update Flow

My end-to-end update process for packages looks like the following:

![package update flow]({{site.ur}}/img/package-update-flow.png)

1. There's a vendoring workflow that is scheduled daily, which just runs `vendir sync` and checks-in the result. This adds any new package versions to the `packages/vendored/` folder according to the package specification in `vendir.yml`
2. Off the back of this, additional workflows are triggered to check-in the manifests to the `sync/prod` folder then push the changes to a branch and raise a PR
3. I manually review the PR and approve, merging into the main branch. This triggers the automatic deployment of the changes
3. ArgoCD deploys updated packages in the `sync/prod` folder (via its continuous reconciliation loop)

With that in mind, we can go on to measure the cadence of this process, in terms of *lead time* and *frequency*.
 
# Measuring Lead Time

Lead time is the measure of how long this update process takes. This will tell us how long our deployed version lags behind where we want it to be. In general terms, this is the time interval between when an updated package was first discovered, to when it was deployed in prod. 

For the workflow here, we will assume ArgoCD works fairly quickly, so its lag in deploying won't be significant and can therefore be ignored. So the query becomes: "How long does it take for changes to progress from `packages/vendored` to `sync/prod`? To find this out we should look at each package vendoring event, then for each event find the next time the same package was deployed. [ It has to be this way, and not backwards from deploys to vendoring events as there may be multiple vendored versions that are - effectively - all deployed in one deploy ].

![package update events](img/package-update-events.png)

In practice, this becomes two Materialized Views in Postgres:
- `package_folder_commits` classifies file changes in commits per-package and per-purpose (vendoring, deploying,etc)
- `package_commit_pair_cause_to_deploy` pairs up vendoring package changes with the subsequent package deploy, and calculates the time difference between the two commits as the `days_between_vendor_and_deploy` column

Based on this, we can get the deployment lag for each package update by just querying the view:

```
select deploy_commit_package, cause_commit_id, deploy_commit_id, days_between_vendor_and_deploy 
from package_commit_pair_cause_to_deploy;
```

Defining these views properly does have some tricky parts, and there's some possibility to find anomalies in the data:
- In my workflow, a commit to the deploy folder is made (on a branch) immediately after the vendored changes as part of triggered workflows. The view must exclude this commit and instead only look at the timestamp of when the deployment PR is made. To do this, we need to enforce merge commits, and use only those commits to identify deployment time
- I have changed the deployment process a few times and it can be difficult to compare results between two different processes. It is possible to account for folder restructuring by keeping old & new names in your queries for a few months. I also found that it can be difficult to distinguish between commits that perform package updates and those containing refactoring changes. The only real answer to this is to carefully analyse any anomalous commits that you find.

The last thing we need to do is to create an aggregation of this data so we can track trends over time, but first, let's look at how we can get the number of deployments from these views.

# Measuring Deployment Frequency

Deployment frequency is useful to give us some idea of how much deployment work is being done, that is to say, how many times updated packages are being deployed.

Specifically, here we want to measure just those deployments that are associated with package updates. Since we already had to match up deploy commits with vendor commits to find lead time, we will only consider deploy commits that were matched up with vendor events.

Once the data has been thus filtered, we just need to count the number of unique deploy commits. We can do this based on the views defined in the last section, with the following query:

```
select count(*) from package_commit_pair_cause_to_deploy;
```

To get the deployment frequency, we just need to choose a time period to measure this count over. We'll do this in the next section, when we build out the dashboard.

# Dashboarding

We now have all the raw data we need, so we can start building a Grafana dashboard to make it easy to track trends. As a prerequisite to dashboard installation, you'll need to set up your Postgres data source so the dashboard can query the data.

## Package Lead Time

To get the overall lead time, we'll calculate the mean lag time for all packages deployed in monthly intervals. This will give enough data to aggregate over whilst being short enough to capture changes in performance. Like with SLOs, where it is common to aggregate metrics over a 28-day window, the idea is to gain a high level view of how well the process is working and whether extra effort is needed to improve it. With these type of metrics we're interested in tracking performance over weeks and months rather than hours and days. 

The query to get the trend for the monthly lead time will be:

```
select 
    date_trunc('month',deploy_commit_author_when) as "time",
    max(days_between_vendor_and_deploy),
    percentile_cont(0.5) WITHIN GROUP (ORDER BY days_between_vendor_and_deploy) as "median",
    max(days_between_vendor_and_deploy)
from package_commit_pair_cause_to_deploy
WHERE
  $__timeFilter(deploy_commit_author_when)
group by 1
```
Where this gives us the max,min and median lead times for each month. Note that this calculates values per calendar month, not over windowed periods of time. Its not possible to do the latter in plain Postgres, without relying on the [timescaledb extension](https://docs.timescale.com/api/latest/hyperfunctions/time_bucket/). But this simpler way suits our needs anyway. The corresponding grafana panel will look like:

![lead time trend](img/patching-lead-time-trend.png)

I also included a separate panel just giving the most important figures, the lead time for the current month and the average over the last 3 months.

I found it's also helpful to plot the raw data, so we can see which packages are the outliers. So there are a few different panels on the dashboard relating to lead time:

![lead time panels](img/patching-lead-time-panels.png)

This is our lead time! Happily my package lead time appears to be trending down. Lets look into frequency.

##  Package Deployment Frequency

Similarly to with lead time, we will calculate deployment frequency in each calendar month, counting the number of distinct package deployments:

```
select 
    date_trunc('month',deploy_commit_author_when) as "time",
    count(distinct (deploy_commit_id || deploy_commit_package)) as "total"
from package_commit_pair_cause_to_deploy
WHERE
  $__timeFilter(deploy_commit_author_when) 
  and deploy_commit_parent_folder='prod'
group by 1
order by 1
```

As before, there are also figures showing the deployment frequency in the current month and over the last three months. In this case, I also found it useful to introduce a second query which breaks out the number of deployments by package:
![patching frequency](img/patching-freq-panels.png)

For additional context, the dashboard also includes the same frequency statistics for the vendoring process:
![vendoring frequeny](img/vendoring-freq-panels.png)

It includes a count of all package updates, broken out by package:
![patching count by package](img/patching-count-by-package.png)

Now we have a good set of dashboards to analyse deployment frequency. These figures show patching being consistently done each month, with a few more patches deployed in June due to a need to "catch-up" on some patches not applied in previous months.

# Conclusion

We now have a dashboard that shows how well our process of automated patching is working! At least, how well its working *in terms of its cadence*.

This dashboard covers both Deployment lead time and deployment frequency, making up half of the DORA metrics (link: TODO). So we know now about the cadence of our deployments, and are able to track improvements or deterioration over time. We still don't necessarily know about their riskiness. In a future post, I intend to explore how this can be augmented with additional monitoring data to measure Deployment Success Rate and MTTR, which is the other half of the picture. In the Continuous Delivery model, we want to automate delivery to go fast, but also to eliminate errors. Going faster without a focus on releasing more safely can lead to a less reliable service.

Another important angle to look at is the completeness of the data. In the queries we used in this post we used our knowledge about the structure of the deployment process to gather data. However, this cannot tell us about the coverage of the deployment process. Is the process working correctly for every package, and is the process even used for every package? Are there packages installed outside this process? Tools that just monitor the state of the target system can be useful to check for potential problems. [Version-checker](https://github.com/jetstack/version-checker) can be used to measure the freshness of deployed images - although I've not had success so far in extracting a meaningful metric from the output data. I've had more success with the [kube-trivy-exporter](https://github.com/kaidotdev/kube-trivy-exporter), which scans deployed images to check for CVEs. The measure of "Critical CVEs" is included in this dashboard to highlight any vulnerable images that might have slipped through the cracks of the patching process. There is more to talk about in the realm of monitoring vulnerabilities, from the idea of a ["vulnerability budget"](https://www.usenix.org/conference/srecon19americas/presentation/thomson), to measuring the amount of time spent vulnerable. This is also something I intend to write more about in future.

The Grafana dashboard built in this post can be imported from [here](https://grafana.com/grafana/dashboards/14970), and uses a postgres datasource called `askgit`.
