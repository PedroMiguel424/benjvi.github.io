---
layout: post
title: "Cloud Policy As Code Pt 2: Applying Policies to AWS with Cloud Custodian"
categories: [technology]
image: ibelonghere.png
---

In the [previous post (link TODO)]() we looked at the motivations for Cloud-Policy-As-Code, we made an informal taxonomy of the different types of policy that exist, and we made a survey of some of the different tools for applying policy that exist. If you want some broader context on Policy-As-Code, you should read that now. In this post we are going to look at how to apply a few policies on AWS using Cloud Custodian. As mentioned last time, this is an open source tool that you will run, typically as a Lambda, to analyse preexisting resources and apply some policies. It has a simple json DSL for writing policies, generally good coverage of AWS resource types, and seems generally useful in the area of policies that are just a bit too complex to express with something like AWS config. And, since its open source, if there is some feature you want that's missing you can just add it. Speaking as a contributor, PRs have been welcomed and it is (generally) easy to add new resources and actions.

## Configuration Change Monitoring

In this first section we are going to look at how, as platform engineers, we can get useful information about the platforms we are building. Over the last couple of years I have done several installations of Kubernetes. To start with, we were just using Terraform and Ansible to perform the installation. These have the advantage of being declarative and also quite decomposable. In other words, we are able to take existing Terraform configs or Ansible runbooks and reuse the definitions, just changing the resources or roles that need to be different for a particular installation. This still works pretty well, but over time the community has made of lot of effort to introduce further automation and reduce the barrier of entry to doing the installation. Thus there are now a handful of different specialised deployment tools available. You can see a list of sanctioned tools in the Kubernetes documentation. On AWS right now, the default choice would be to use [kops]().

## KOPS

So, at some point last year I started learning to use kops.  Reading the docs and looking at the options available, everything looked great. But once I started trying to deploy things it started to become more difficult. Different combinations of options are not independent and you need to know how the options interact with each other. Working out the correct combination of options took some time - not as much time as using terraform did - but still, more than expected. 

The reason is that kops is doing a lot of automation. Although the interface looks (relatively) simple, the process of deployment orchestration it is doing behind the scenes is complex. So the interface is now too simple for us to give us an understanding of the deployment process. More worryingly from an operational POV, it is too simple to give us a good understanding of what resources we actually end up deploying. This is where policies can help give more insight into running infrastructure.

### Aside: The Future

Kubernetes has been an extremely popular platform, becoming the only real choice in the container orchestration space over the last couple of years. So much so that AWS feels like that they need to offer Kubernetes as a first class citizen on AWS with the (imminently GA) EKS service. As a managed service, this saves a whole lot of operational support so this is likely to be the recommended way to run Kubernetes on AWS. While there is not much point observing the mechanics of a service that you don't operate, there will continue to be other complex distributed platforms that are not offered as managed services on your cloud platform. These will benefit from a policy-based approach to configuration change monitoring. Amongst technologies that Opencredo works with, Kafka, Cassandra and DCOS come to mind, but there are many others.

## Risks

Before we can write policies we need to think about kinds of resources and approaches to deployments that might cause some risks. After a good bit of thought we can come up with something like the following, risks organised by possible downside:

#### Data Breach 

- Publicly accessible Kops state

#### Data Loss

- etcd nodes with no persistent disk

#### Resource Wastage

- old test clusters lying around
- incorrectly sized nodes

#### Potential Attack Vector

- Master or worker nodes exposed directly to internet
- Nodes resolvable on public internet
- Old/Unpatched nodes


Since we want to distinguish between resources of the same type but with different purposes, we also need to put in place some naming and/or tagging conventions. Kops already puts in place some tags for this so we are going to use those in our policies. 

## Policies 

Once we've identified the risks, its easy to rewrite them as a policy to be enforced. Similarly, translating the human-readable policy to one that can be executed by Cloud Custodian is simple:

### No Public DNS Allowed

```
policies:
  - name: ec2-public-dns
    resource: ec2
    filters:
      - PublicDnsName: present
      - "tag:KubernetesCluster": present
```

### No Public IP Allowed

```
policies:
  - name: ec2-public-ip
    resource: ec2
    filters:
      - PublicIpAddress: present
      - "tag:KubernetesCluster": present
```

### No ephemeral disk on master 

```
policies:
  - name: ec2-ephemeral
    resource: ec2
    filters:
      - type: value
        key: RootDeviceType
        op: ne
        value: ebs
      - "tag:KubernetesCluster": present
      - "tag:k8s.io/role/node": present
```

### No instances using an AMI older than 2 months

```
policies:
  - name: ec2-old-amis
    resource: ec2
    filters:
      - type: image-age
        op: ge
        days: 60
      - "tag:KubernetesCluster": present
```

## Running these policies

An easy way to run Custodian is in Docker (assuming Custodian policies are in the `custodian-policies` subdirectory and we are using the user's AWS credentials file):

`docker run -it -v $PWD/custodian-policies:/src/policies -v $HOME/.aws:/root/.aws --entrypoint=/bin/sh capitalone/cloud-custodian`

Since the policies don't specify any deployment mechanism, they get run directly by the Custodian CLI:

`custodian run -s out /src/policies/*`

All the policy files and commands, as well as the kops commands I used for setting up and destroying clusters is in the Github repository [here (TODO)]().

## Actions

Eagle-eyed readers will have noticed that, despite my insistance earlier that policies should be associated with actions, these policies did not specify an action. So, while the custiodian 'policies' we wrote so far are userful for monitoring configuration changes, as proper policies they are incomplete. A policy that is not enforced is little more than a philosophical exercise, after all. Let's fix that now.

According to the nature of the risk, we may want to enforce different actions across different environments. So, in a development cluster we may not care if the master has an ephemeral disk or not. We probably just want to warn the operator that he is reducing durability unnecessarily. In this case, we cannot even do much for production environments, since it will require an operator to rebuild the cluster masters (not a trivial). However we want to send a page instead of a warning - this should be fixed with urgency to avoid any chances of real data loss. Ultimately, here we end up sending different types of messages. 

Development policy:

```
policies:
  - name: ec2-ephemeral
    resource: ec2
    filters:
      - type: value
        key: RootDeviceType
        op: ne
        value: ebs
      - "tag:KubernetesCluster": present
      - "tag:k8s.io/role/node": present
    actions: 
      - type: notify
        to: ['notifications@example.com']
        transport:
          type: sqs
          region: eu-west-1 
          queue: my-warning-messages 
```

Production policy:

```
policies:
  - name: ec2-ephemeral
    resource: ec2
    filters:
      - type: value
        key: RootDeviceType
        op: ne
        value: ebs
      - "tag:KubernetesCluster": present
      - "tag:k8s.io/role/node": present
    actions: 
      - type: notify
        to: ['notifications@example.com']
        transport:
          type: sqs
          region: eu-west-1 
          queue: my-alerts 
```

Since the other policies are security-related, we have to apply them uniformly at a minimum within the VPC boundary (but to avoid accidents, within the account boundary is probably better). So we can use the same policy across environments. With Cloud Custodian, we can initially mark a resource for deletion, giving an operator time to properly decommission the system. This is what we do here (this new action block will be unchanged for the three policies): 

```
policies:
  - name: ec2-public-dns
    resource: ec2
    filters:
      - PublicDnsName: present
      - "tag:KubernetesCluster": present
      - type: marked-for-op
        op: terminate
    actions:
      - terminate
```

## Policy Wish-List

While the policies so far were easy to write as custodian policies, there are other types of policy which as easy for us to describe informally, but which are a bit more tricky to translate into code. Examples of such policies might be: 

*“EBS volumes on master must be backed up”*

*“Clusters with < 5 worker nodes must have 1 master, otherwise must have 3 masters”*

In general, it looks like being able to make multiple API queries and join the result is something that would be really useful. Custodian only supports specific queries which would involve fetching additional resource data, for example: 

*“AMI images in use must have an approved tag”*

This is implemented with a specific boolean option and the join is made within the custodian application code. Arbitrary joins are not supported within custodian, and its not clear whether they should be. It would complicate the language a lot just to support joining, and dealing with the structure of the result is more different as the fields available depends on join we performed.

## Use of General Purpose Query Languages

At this point, it might be better if our tool just supported the SQL standard. Having a DSL is good for doing specific things within a domain, but for doing more arbitrary things a general purpose query language is better. Why reinvent the wheel anyway? SQL is well-proven for dealing with structured data, it is well-known, and easy to write queries with.
 
Of course using SQL doesn't solve all our problems. SQL databases work with data on a single node, so it doesn't say anything about how we retrieve the data from an API to start with. This is especially problematic in case our cloud estate is particularly large. It also doesn't help us in specifying actions, which are always domain specific. An examplar of this approach is Facebook's project [osquery](https://osquery.io/) which does something similar for analysing the configuration on fleets of computers. This only restricts itself to dealing with querying though, and not with the subsequent actions.

Another approach which may make sense if we are only talking about querying is the use of document databases. With something like elasticsearch you also get the possibility to do full text search against you resources which may be particularly useful when (e.g.) looking for particular types of policies. However, since it deals with semi-structured data, we need to be more careful when implementing our domain-specific actions. 

## Summary

In this pair of posts, we looked at the whys and wherefores of Policy-As-Code in cloud platforms. Previously we gave the context, and a survey of the space, and now we have looked at how you can get started with using Cloud Custodian to write policies for your AWS resources. We used Kubernetes as our example, but maybe you can think of some policies that you may be able to apply to your own infrastructure (you can see what resources, filters and actions are available in the [Cloud Custodian documentation]()). We also saw the limitations of using Custodian's very simple DSL for more complicated queries - for these types of queries SQL or elasticsearch queries look more appropriate. What do you think? What kinds of configuration problems do you want to avoid and how have you found the best way to do it? I am interested to hear your ideas in the comments. 	


