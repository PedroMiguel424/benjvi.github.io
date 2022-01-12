---
layout: post
title: "Measuring Patching Cadence on Kubernetes with `askgit` and Postgres"
categories: [technology]
---

![patching dashboard](../img/full-patching-dashboard.png)

I operate a Kubernetes cluster at home, running on Raspberry Pi's, which hosts various applications. To augment the platform's capabilities, a bunch of supporting third party platform extension services also run on it, things such as:
- Weave Network Plugin
- MetalLB
- cert-manager
- Prometheus & Grafana
- Gatekeeper

When you run services, you also have to worry about keeping them up-to-date, for a few reasons:

- As time passes, more and more CVEs are discovered for old software, multiplying the risk of being hacked. It's particularly risky for systems accessible from the public internet, as is the case for some services I run.
- Even software that is not vulnerable may also become problematic. If other (vulnerable) components are upgraded around an unchanged piece of software, newer versions may be incompatible with older APIs, and integrations may break.
- Most software is broken on some level. You often run into bugs and feature gaps - where your use case is different from what the authors expected. Many of these issues are fixed in software updates.

For these reasons, it's important not just to install the software, but also to keep it updated.

# Upgrades

Unfortunately, designing your system for upgrades requires more care than just installing a package. You should:
- Keep track of the current state of your infrastructure using Infrastructure as Code, aka package manifest YAML files checked-in to git
- Keep track of where to pull the package from, and possibly define an upgrade process too. A tool like [Vendir](https://carvel.dev/vendir/docs/latest/) can be used for this.
- Keep track of any customizations you made to a package, and define a repeatable process for applying them
- Define some process for keeping secrets in-sync with the deployed packages
- If you have multiple environments, define a process for rolling out updates sequentially to those environments, and for giving the appropriate environment-specific parameters

None of this comes for free - each aspect requires some engineering effort. And when things get more complex, it's easy to lose sight of the big picture. It's important to make sure we aren't just cargo-culting practices. We don't want automation for the sake of automation - we want to achieve something with them. Namely, that upgrades are applied more quickly when they are available. Therefore, we should *identify the metrics we want to improve*, and *measure their trends*.

# Measuring Progress

To choose appropriate metrics, we can look to the ideas in the world of Continuous Delivery. A lot of studies have been done in this area about good practices for teams developing and deploying software. Even though we aren't *developing* this software ourselves, we can draw on the same ideas.

In particular, the so-called [DORA (DevOps Research and Assessment) metrics](https://www.blueoptima.com/blog/how-to-measure-devops-success-why-dora-metrics-are-important) are top-level metrics for teams looking to improve software development performance. In our quest to improve patching, it will also be important to track these metrics:
- (Increasing) Deployment Frequency
- (Decreasing) Lead Time for Delivery
- (Decreasing) Mean Time To Recovery (MTTR) 
- (Increasing) Proportion of successful releases

Importantly, these are precise things that we can quantitatively measure. At a high level, you would calculate them something like this:
- *Frequency* = `(number of deployments) / (time period)`
- *Lead time* = `(time of production deployment) - (time of associated code commit)`
- *MTTR* = `(time an incident began) - (time an incident ended)`
- *Change Failure Rate* = `(number of releases triggering incidents) / (number of releases) = 1 - proportion of successful releases `

In broad terms, these four metrics relate to (1) counting and gathering timings over deployment events (Deployment Frequency & Lead Time) and (2) relating those deployment events to counts and timings of service incidents (MTTR & Change Failure Rate).

Using a GitOps repo, you can measure *Deployment Frequency* and *Lead Time* based entirely on the Git history. This is what we're going to dig into in subsequent sections of this post. 

Before that, a word of warning. In the Continuous Delivery model, we want to automate delivery not only to go fast, but also to eliminate errors. Trying to optimise these metrics to go faster without also focusing on releasing more safely could lead to *worse* reliability. So, for a *complete* picture of your delivery performance, it is always recommended to *also* track measurements of deployment risk via the MTTR and Change Failure Rate metrics. These would be measured using data from your Incident Management system. 

With that said, let's dig into what git can tell us about our deployment performance. To help us with this, we'll use `askgit` with a Postgres database. `askgit` is a CLI tool to query git repo history via SQL. 

# Introducing [`askgit`](https://github.com/askgitdev/askgit)

Exposing the data in your git history means you can ask all different sorts of questions. There is a `commits` table so we can ask for a list of all the commits, similar to what you would get with `git log`:

```
askgit 'select * from commits'
```

To add the details of files changed in each commit, we'll cross-reference the `stats` table. This will allow us to identify commits where a new package was discovered and fetched (i.e. "vendored"). The workflow fetching new packages will create a commit with the changes, checking in packages to the `packages/vendored` directory. This allows us to identify updates to vendored packages: 

```
askgit "select * from commits, stats('', commits.hash) where file_path like 'packages/vendored/%'"
```

Similarly, we will get prod deployment events when commits include changed files representing the desired state of prod - which are those under `sync/prod`:

```
askgit "select * from commits, stats('', commits.hash) where file_path like 'sync/prod/%'"
```

The presence of a GitOps tool like ArgoCD makes sure that these updates made to a Git repo produce actual deployment events. 

The other handy feature of `askgit` is the ability to export data to an SQLite database, with a command like:

```
askgit export askgit-commits-stats-db.sqlite3 -e commits -e "select * from commits" -e stats -e "select * from stats('', commits.hash)" 
```

Because of some schema changes that have happened in askgit over time, we need to add some column remapping so that the dashboard queries will work properly later on:

```
askgit export askgit-commits-stats-db.sqlite3 -e commits -e "select hash as id,* from commits;" -e stats -e "SELECT commits.hash as "commit_id", stats.file_path as "file", stats.additions, stats.deletions FROM commits, stats('', commits.hash)"
```

SQLite is well supported by many tools, so once you have an SQLite database, there are lots of tools that can further process the data. I used `pgloader` (with the [appropriate config](https://github.com/benjvi/measuring-patching-cadence/blob/main/askgit-sqlite-to-postgres.txt)) to load the data into Postgres so that we will be able to query it from Grafana. You will need a Postgres server set up, then this config will need to be customized with its connection details. Then, to load the data based on that config you will run:

```
pgloader askgit-sqlite-to-postgres.txt
```

I also created [a Kubernetes `CronJob`](https://github.com/benjvi/measuring-patching-cadence/blob/main/cronjob.yml) you can run to continually load the latest data from your repo (make sure you update it to point at your repo!).

# Package Update Flow

My end-to-end update process for packages looks like the following:

![package update flow]({{site.ur}}/img/package-update-flow.png)

1. There's a vendoring workflow that is scheduled daily, which runs `vendir sync` and checks-in the result. This adds any new package versions to the `packages/vendored/` folder according to the package specification in `vendir.yml`
2. Off the back of this, additional workflows are triggered to check-in the manifests to the `sync/prod` folder, then push the changes to a branch and finally raise a PR
3. I manually review the PR and approve, merging into the main branch. This triggers the automatic deployment of the changes
3. ArgoCD deploys updated packages in the `sync/prod` folder (via its continuous reconciliation loop)

With that in mind, we can go on to measure the cadence of this process, in terms of *lead time* and *frequency*.
 
# Measuring Lead Time

Lead time is the measure of how long this update process takes. This is the most important metric to optimize in patching, as it will tell us how long our deployed version lags behind where we want it to be. If our lead time is more than a few days we may start to incur some of the risks of running outdated software. The total lead time is the time interval between when an updated package was first discovered, to when it was deployed in prod. 

Let's apply this to the actual deployment workflow described in the previous section. We will assume ArgoCD works fairly quickly, so its lag in deploying can be ignored. So the query becomes: "How long does it take for changes to progress from `packages/vendored` to `sync/prod`? To find this out, we should look at each individual pair of commits. We start by considering each package vendoring commit. For each commit, we can then search for the next related deployment commit. 

![package update events](../img/package-update-events.png)

In practice, this becomes two Materialized Views in Postgres:
- [`package_folder_commits`](https://github.com/benjvi/measuring-patching-cadence/blob/d569177967bf4f583a44e9f66eee709f4c603981/create-package-deploy-view.sql#L4) classifies file changes in commits per-package and per-purpose (vendoring, deploying,etc)
- [`package_commit_pair_cause_to_deploy`](https://github.com/benjvi/measuring-patching-cadence/blob/d569177967bf4f583a44e9f66eee709f4c603981/create-package-deploy-view.sql#L46) pairs up vendoring package changes with the subsequent package deploy, and calculates the time difference between the two commits as the `days_between_vendor_and_deploy` column

Create the views by downloading [this SQL file](https://github.com/benjvi/measuring-patching-cadence/blob/main/create-package-deploy-view.sql), setting environment variables for your Postgres, and running:

```
psql -f "create-package-deploy-view.sql"
```

Based on this, we can get the deployment lag for each package update by just querying the view:

```
select deploy_commit_package, cause_commit_id, deploy_commit_id, days_between_vendor_and_deploy 
from package_commit_pair_cause_to_deploy;
```

Defining these views does have some tricky parts, and there's some possibility to find anomalies in the data:
- In my workflow, a commit to the deploy folder is made (on a branch) immediately after the vendored changes as part of triggered workflows. The view must exclude this commit and instead only look at the timestamp of when the deployment PR is made. To do this, we need to *enforce merge commits*, and use only those commits to identify deployment time
- It can be difficult to consistently compare results when the deployment process changes. I did manage to account for some folder restructuring I did by keeping old & new names in the queries for a few months. However, in general, commits containing refactoring changes have been difficult to handle. The only real answer I found is to individually analyse any anomalous commits.

The last thing we need to do is to create an aggregation of this data so we can track trends over time, but first, let's look at how we can get the number of deployments from these views.

# Measuring Deployment Frequency

Deployment frequency is useful to give us some idea of how much deployment work is being done, that is to say, how many times updated packages are being deployed. In the context of patching, more deploys is not necessarily better, as it's not a bad thing if software doesn't *need* patching. Saying that, most teams I've worked with are always behind on patching, and at a minimum, this metric should show that at least *some* patching is going on.

Specifically, here we want to measure just those deployments associated with package updates. There may be deployments associated with other events such as configuration changes. Since we already had to match up deploy commits with vendor commits to find the lead time, we will only consider deploy commits that were matched up with vendoring commits. This ensures only deployments associated with package updates are counted.

Once the data has been filtered, count the number of unique deploy commits. We can do this based on the views defined in the last section, with the following query:

```
select count(*) from package_commit_pair_cause_to_deploy;
```

To get the deployment frequency, we'll need to choose a time period to measure this count over. We'll do this in the next section, when we build out the dashboard.

# Dashboarding

We now have all the raw data we need, so we can start building a Grafana dashboard to make it easy to track trends. As a prerequisite to dashboard installation, you'll need to set up your Postgres data source so the dashboard can query the data.

## Package Lead Time

To get the overall lead time, we'll calculate the mean lag time for all packages deployed. We'll calculate this in monthly intervals. This will give enough data to aggregate over, whilst being short enough to capture changes in performance. Like with SLOs, where it is common to aggregate metrics over a 28-day window, the idea is to gain a high-level view of how well the process is working and whether extra effort is needed to improve it. With these type of metrics, we're interested in tracking performance over weeks and months, rather than hours and days. 

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
Where this gives us the maximum, minimum and median lead times for each month. Note that this calculates values per calendar month, not over windowed periods of time. It's not possible to do the latter in plain Postgres, without relying on the [timescaledb extension](https://docs.timescale.com/api/latest/hyperfunctions/time_bucket/). But this simpler way suits our needs anyway. Sometimes simplicity is a virtue. Calendar months are easy to understand. So, the corresponding Grafana panel will look like:

![lead time trend](../img/patching-lead-time-trend.png)

There is also a separate panel giving: the most important figures, the lead time for the current month and the average over the last 3 months.

I found it's also helpful to plot the raw data, so we can see which packages are the outliers. So there are a few different panels on the dashboard relating to lead time:

![lead time panels](../img/patching-lead-time-panels.png)

This is our lead time! Happily, my package lead time appears to be trending down. Let's look into frequency.

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

As before, there are also figures showing the deployment frequency in the current month and over the last three months. In this case, I also found it useful to introduce a second query, which breaks out the number of deployments by package:
![patching frequency](../img/patching-freq-panels.png)

For additional context, the dashboard also includes the same frequency statistics for the vendoring process:
![vendoring frequency](../img/vendoring-freq-panels.png)

It includes a count of all package updates, broken out by package:
![patching count by package](../img/patching-count-by-package.png)

Now we have a good set of dashboards to analyse deployment frequency. These figures show patching being consistently done each month, with a few more patches deployed in June due to a need to "catch-up" on some patches not applied in previous months.

# Setup Recap

To get the dashboard up and running, we have now:

- Modified the files [`askgit-sqlite-to-postgres.txt`](https://github.com/benjvi/measuring-patching-cadence/blob/main/askgit-sqlite-to-postgres.txt) and/or [`cronjob.yml`](https://github.com/benjvi/measuring-patching-cadence/blob/main/cronjob.yml) with the details of your Postgres and your git repo to be analysed
- Then loaded data into Postgres:
 - EITHER by manually extracting and loading data by running:
   - `askgit export askgit-commits-stats-db.sqlite3 -e commits -e "select hash as id,* from commits;" -e stats -e "SELECT commits.hash as "commit_id", stats.file_path as "file", stats.additions, stats.deletions FROM commits, stats('', commits.hash)"` 
   - `pgloader askgit-sqlite-to-postgres.txt`
   - `psql -f "create-package-deploy-view.sql"`
 - OR by exracting and loading data periodically by applying the Kubernetes CronJob: `kubectl apply -f cronjob.yml` and waiting for it to run at least once
 
We may now setup an `askgit` Postgres datasource in Grafana and import the [dashboard](https://grafana.com/grafana/dashboards/14970)

# Process Bypass

This dashboard contains the main metrics we wanted to measure, so now we can put our minds to the limitations of our measurements, and how they fit into a broader monitoring strategy.

Here we are only measuring packages that are deployed or patched through a defined, automated, process. Any packages deployed outside of this process will not be considered. Therefore, tools that monitor specific properties for all items on the runtime system can be a useful complement to these measurements, providing assurances for properties like version freshness, number of CVEs and allowing to make some judgements on overall vulnerability. To highlight this, the dashboard includes a panel using Prometheus with the [kube-trivy-exporter](https://github.com/kaidotdev/kube-trivy-exporter) to display the number of images with critical CVEs.

As mentioned earlier, it may also be advisable to track and think about metrics relating to deployment risk as another complement to these velocity-related metrics.

# Conclusion

We now have a dashboard that shows how well our process of automated patching is working! At least, how well it's working *in terms of its cadence*.

This dashboard covers both deployment lead time and deployment frequency, making up half of the DORA metrics. So we know now about the cadence of our deployments, and are able to track improvements or deterioration over time. Over the months I've been using the dashboard, it has indeed given me a nudge to be more attentive to patch deployments whenever I have been neglecting them.


