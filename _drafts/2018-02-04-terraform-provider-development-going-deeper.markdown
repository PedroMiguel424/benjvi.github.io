---
layout: post
title: "Terraform Provider Development: Defining Resources"
categories: [technology]
image: ibelonghere.png
---

One of the nice things about Terraform, and one of the reasons it has been so successful, is that it is very easy to extend with new (cloud) APIs. Terraform offers scaffolding you can build upon to create new providers and new resources. For a new resource, you only need to create:
 - a resource schema definition
 - a set of CRUD methods that wrap API methods for the relevant resources 
 - translations of the API resource representations into the defined schema
 
 On the provider level, you need to define little more than:
 - the set of resources that the provider can manage
 - how to construct the API client used to interact with the backend 

There are a bunch of useful resources on how to get started with provider development, foremost upon them the [HashiCorp Guide](https://www.Terraform.io/guides/writing-custom-terraform-providers.html) and [Terraform Contributing Guide](https://github.com/hashicorp/Terraform/blob/master/.github/CONTRIBUTING.md). [This article](http://container-solutions.com/write-Terraform-provider-part-1/) is also nice, covering some of the same material just in a different way. With the mechanics already covered, here we will illustrate some of the choices you will need to make in translating your API definitions into Terraform resources, and give some guidance for how to make these decisions. This is where the real meat of provider development is. Hopefully, this article will also leave you with a deeper understanding of what a resource is supposed to look like, and leave you well prepared for the kind of discussions around style and design that take place in Terraform issues and PRs.

## Writing The Schema

### Types

When defining a new resource, the first step I take is to transcribe the fields from the API docs into a Terraform resource. The name of each Terraform attribute should generally be the same as the name of the object in the API (the convention in Terraform is to use camel-casing, which also typical in JSON). Since the types that the Terraform schema supports is more constrained than general datatypes in Go, we need to do some simple mapping:
  - Ints, Strings and Booleans map directly to the Terraform types `TypeInt`, `TypeString`, `TypeBool`
  - For some simple types like `Float`'s and `Time`'s it makes sense to serialise them as `TypeString`. However for most simple structs (objects), you should use Terraform's way of defining nested objects (see below)
  - Go itself doesn't have much support for enums, however, if the data is of this nature this would be handled by using the `validation.StringInSlice` function from the *terraform/helper/validation* package as the `ValidateFunc` of the attribute
  - Another validation function I make use of frequently is `validation.IntInRange`
  - Other more complex types can be specified, but need a bit more discussion (see "Schema - Choosing Data Structures" and "Schema - Nested Data Structures") 

### Specifying Attributes' Lifecycles 

In the Terraform schema, we don't just specify types, but also who should specify it and whether a value is mandatory. If the API is reasonably 'RESTful', modelling this can also be a fairly mechanical process of applying simple rules:

- Required attributes for PUT/POST should be the `Required` fields on the Terraform resource
- Do similarly for `Optional` fields. Sometimes an API has additional methods to further configure an already created resource, but these should also be here. Terraform should flatten the configuration process into a single action ( implementation-wise this could be split between Terraform's `Create` and `Update` functions)
- An attribute returned in the result of any create/update/read call which is `Optional` or read-only is marked as `Computed`. Normally, all values would be present but there are some values like passwords and private keys that only get returned once on creation or update
- Any attribute that can be specified on creation but is not accepted by an update call (either PUT/PATCH/etc) should be marked with `ForceNew`
- If any optional value has a simple default value I prefer to specify this value as `Default`. This means a Terraform user will be able to see the value that will be given as part of their plan. If the default is unknown or indeterminate, then fall back to specifying `Computed`. The reason why will be discussed in "Setting Defaults and Validating User Inputs" 
 
### Choosing Data Structures

Terraform has List, Set and Map data structures available for attributes, and *in general* you should expect to use them as you would learn in CompSci 101. In other words, use lists when ordering is important, use maps when your data is made of key-values and use sets to guarantee objects in your list are unique. However, data structures in Terraform do have their limitations.

Maps can hold Ints, Booleans and Strings but **not** a combination of the three, as they might do in JSON, or in Go. They also cannot hold other maps, lists or sets. So they are quite constrained, compared to maps in most languages. See [this issue](https://github.com/hashicorp/terraform/issues/6215) for more discussion of this. For those that don't want to read the whole thing, just note that these constraints are likely to change some time after [HCL2](https://github.com/hashicorp/hcl2) is introduced.

When using a set, you should be aware that by default the items are hashed using all their attributes. This is so that objects dont get overwritten erroneously. You can override this using a custom HashFunc to enforce uniqueness by some key field. 

### Nested Data Structures

Putting a single nested object (ie with a one-to-one relation) is rather awkward in Terraform. Normally you would use a map for this, but that is not supported. So the normal convention is to use a `TypeList` with `MinItems` and `MaxItems` both set to 1. This implementation is simpler than using a `TypeSet`, since ordering is not a worry with these constraints. By contrast, when the resource holds multiple objects, this can be modelled well with a `TypeSet`.

One thing that gave me some pain to start with nested objects is that if some field is not correctly when setting back a nested field into the resource data is that if one field is modelled incorrectly the whole assignment will fail. Since it is not normally necessary to check the error when setting simple schema fields, I omitted it there as well. This made things difficult to debug! Don't do this like I did, you should always do an error check when setting a complex object on the resource data.

### Aligning the Schema with your API

As mentioned earlier, when I start writing a resource I usually start by copying the API resource definition as the Terraform resource schema. But that is not sufficient to define the resource. As we have seen, there are some extra constraints in Terraform schema. A problem I seem to run into frequently is where the API effectively has union types. If the API sometimes returns a string and sometimes and object, or an array, then we need to declare multiple fields in the Terraform schema , one for the schema, one for the object and one for the array. Then we would need to write some logic to correctly transform things in the `Create`, `Update` And `Read` functions. The same problem can occur with items in lists, or sets with the solution being similar.

In those cases, differences between the Terraform resource and the API resource are inevitable, but there are other cases where you may want to use a different representation in Terraform for stylistic or implementation reasons. Since nesting objects in Terraform looks rather awkward, at least in the code, it might be tempting to flatten small nested objects. Or in cases where the API exposes an overcomplicated interface, it might be tempting to make it cleaner. Neither of these things are necessarily bad, but they should be approached with caution. Since Terraform manages objects throughout their lifecycle, it is somewhat understandable that its representation might be slightly different than that in the API. However, it is simpler for users if the representation is the same everywhere. This should provide advantages for maintainance too. So, the benefits from simplifying or flattening need to outweigh those costs.

### Setting Defaults and Validating User Inputs

Wherever possible, it is usually desirable to specify a default for an attribute, either as a simple value with `Default` (cannot be a data structure) or a calculated value with `DefaultFunc`. This allows the user to see at the time of doing the plan what the created resource will look like, although it does come at the cost of additional code to update whenever the API changes. In general though, it seems to make sense to set `Default` or specify a *simple* function for `DefaultFunc`. 

Similar logic applies when writing validation for the attributes values users provide. If you specify a simple `ValidateFunc` on your attribute, it means that users don't have to run `apply` to find out if their config is invalid, they can find out as soon as Terraform parses the config - either in `validate` or in `plan`. 

## Create and Update 

I tend to group the create and update functions these together, both conceptually and in the layout of the code, because they tend to be closely related. If the API is RESTful, and both POST and PUT exist as create and update methods, then the two methods should look almost identical. The only difference is that the `Create` method must set the ID on the Terraform resource.

In terms of layout, the struct you will send to the API creation should be first declared. The declaration should also specify all attributes that are either `Required`, or `Optional` with a default (easy to miss!). No guard is needed because Terraform guarantees these will always be set with the specified type. On the other hand, you will need a separate guard for each `Optional` value (with no default) to check if its set, and assignment to the API struct accordingly. 

Since Terraform provides the values held in data structures as `interface{}` there is normally some transformation work to do to get them into the type that the API expects. Normally I would write this code in a separate helper function, otherwise the main function will get too long and unweildy. A nice naming convention I like to follow with these is to call them `expandXXX`, with XXX being the logical name of whats being expanded. Conversely, when items are transformed the other way on `Read`, the tranforming functions are called like `flattenXXX`.

One thing that is still tricky to handle in Terraform is the difference between a value provided explicitly in the config and those where the value is not provided explicitly but is present due to a default value, or getting calculated. Terraform can tell you if a non-empty value has been provided at least once for this resource through the `resourceData.getOK` method, but it cannot tell you if the value is specified in the current plan. In case empty values are meaningful for you, you migth be out of luck - `getOK` cannot tell you if anything at all about empty values (although the new [`getOKExists`](https://github.com/hashicorp/terraform/pull/15723) might save you). Although these functions don't cover all possible cases, they just cover a good portion. Especially when you consider that you can also use the `hasCahnge` method to find out if an attribute value is different than in the previous state. 

## Import

When resources exist that were not created by Terraform, users often want to be able to import them to be managed by Terraform. Especially if you are creating a new resource, users couldn't manage it with Terraform before! So its important to also implement Import for your resources. 

There are some tricky parts with Import though. In some cases the ID for your resource may not be sufficient to lookup the resource for the API (though it should always be unique!). Then, you should ask the user to give the ID in a format that you can parse and use to lookup the resource. In the Import function, you can convert this ID to the same one you would set on `Create`.

You also need to make sure that any one-time values you set on `Create` are set here. 

## Read And Delete

The most important thing in the `Read` method is to make sure that all the attributes are set as they are returned from the API. Here it doesn't matter if they are `Required`, `Optional` or `Computed`, you should set them all. The exceptions being some attributes you specifically know are immutable and can set once on `Create`. Terraform while continually try to update the resource if you don't do this, trying to set a value in the state. This will cause any tests you define to fail too. In case the API normalizes or makes some other predictable change to values you specify,  you need to write a `DiffSuppressFunc` on the attribute to stop Terraform continually doing spurious updates.

As mentioned previously, in the `Read` function you will need to flatten API types to get them in the right format to be written to the resource data. It is important to check errors for this to have some visibility on anything going wrong.

The other thing that is important for both the `Read` and `Delete` methods is that the function completes successfully when the resource is no longer present at the API (ie you receive a 404). You should not throw an error in this case. In the case of the `Read` method it is also important to set the ID to `""` (empty string) - this tells Terraform that it needs to recreate the resource. Terraform has an explicit Exists method that you could define to do the same thing, but it doesn't seem worthwhile to make the extra request just for this.

## Testing The Resource 


### (Regular) Acceptance Tests

Most of the work of testing resources is done by simply defining a terraform config and a set of checks you want to run after Terraform has run `apply` on that config. When you feed these arguments to the terraform test framework, it will do the co-ordination work of running the apply, the checks and also running `destroy` afterwards. Additionally, if the plan is not empty after the destroy, it will fail the tests (this catches many error modes, such as attributes never getting set). 

For this reason, its normally not necessary to add a check that every attribute is set correctly - this will be caught without any explicit check. It is probably appropriate to check that the resource actually gets created at the API, and it may be important to test that any invariants you are enforcing in the CRUD functions actually take effect. 

In terms of test cases, I would suggest to at a minimum make sure your tests cover a basic apply, and update (if defined) and that you can handle manual deletions. In addition to this you should define an Import test. Whether other tests add value depends on the logic in your resource. Since each test goes to the real API they are relatively costly. For this reason its helpful if you parameterize and randomize any reused config files so concurrent usage of them doesn't conflict. Then you can run the tests in parallel. 

### Import Tests

Import tests are also acceptance tests, using the same test framework. The sequence here is slightly different though. First you will define a  regular test step to create a resource from a config. Then as a second test step you run a different step to import the resource. When you do this you will import it into the same terraform state that you created in the previous step. You will specify the ID from the Terraform config as well as the resource ID to import with (as you do on the CLI). Similar to before, the test framework will check if the attributes resulting from the import match those already existing in the state. So, this test will ensure that resources end up in the same state regardless if they were created or imported.

### Unit Tests

Often, there is very little behaviour in a Terraform resource whose behaviour can be verified independently of the API. The most important things for the resource is if the format of the resources it sends to create/read/update (etc) API calls are as expected, and vice versa that the response from the API matches up with what Terraform expects. For this reason, there are typically relatively few unit tests for Terraform resources. Nevertheless, where there are helper functions which have some business logic inside, e.g. in validation functions, you should have some unit tests to exercise that logic. 

## General Golang Coding Practices

Terraform is one of the nicer Golang codebases I've worked on. So it should be no surprise that it seems like the engineers from Hashicorp are pretty hot on good Go programming practices. If you want to brush up in that area, probably the best place to start is with [Effective Go](https://golang.org/doc/effective_go.html), and following on from that, [this awesome compendium](https://github.com/enocom/gopher-reading-list) possibly has all the resources you will ever need. 

## Closing Thoughts

Its easy to get started developing resources in Terraform, and the helper interfaces that are provided are for the most part logical and intuitive. In particular, the schema abstraction for modelling resources is a very powerful part of Terraform. But when we look a little bit deeper, there are some hard choices you need to make in modelling resources and there are a number of corner cases you are liable to run into, sooner or later. Here, we have shown some important issues you might face, which is certainly more than enough to get started with development. But there is a lot more to learn. We have not even touched on data sources yet! For those wishing to go deeper, you should check out the [github issues](https://github.com/hashicorp/Terraform/issues), which contain a wealth of useful information and also show the story behind design decisions in Terraform. 
