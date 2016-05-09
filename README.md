Realtime Errors Service
===

A simple example of a Node.js service which polls ElasticSearch for new documents (according to a @timestamp field), and outputs them as [HTTP server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events) as they arrive.

This specific service is tailored to our internal “realtime errors” view fed by logs from our web servers. It should be easy to copy and modify for other needs.

No claims of beauty or perfection are made or implied. It is essentially a bodge. However, it has proven surprisingly reliable and useful.


Specific design explanations
---

* Each ElasticSearch polling request has a long timeout. There are no more requests until the current one comes back. This is intentional, so that any flakiness appears on our visualizer with the strength of a genuine catastrophe.

* There is no proper error handling; errors are just dumped (once) to the clients. This is because we haven't ever seen any errors, just occasional slow responses by ElasticSearch or misconfigurations in our load balancer – so I never bothered implementing anything more complicated.


LiveScript
---

This project is written in [LiveScript](http://livescript.net), which is in my opinion still the most perfect JS-compiling macro language yet. Languages without semantically-significant indentation are (of course) clumsy, ugly and a waste of time, and the better-known CoffeeScript is still [fundamentally broken](http://lucumr.pocoo.org/2011/12/22/implicit-scoping-in-coffeescript/).

I have however used [lodash](https://lodash.com/) (`_`) to get the usual helper functions instead of LiveScript's own prelude, as it's probably more widely understood and I remember it better, even if the order of arguments is usually annoying. There are probably better options by now, but it really doesn't seem that important.

Hopefully the code is sufficiently self-explanatory upon reading that none of this matters too much. I'll explain some common confusions.

The `do` keyword is a bit weird and loosely means “do “something” with the following block”. Most common uses:

* Introduce an object literal without braces;
* Treat the following list as arguments to the function that's been given the `do`;
* Immediately invoke the given closure.

… Well, you get used to it.

One other thing to watch out for is `->` vs. `!->`. Functions, in LiveScript, like in Ruby or various other crazy languages, implicitly return their last expression when defined with `->`.

This is really nice for extremely trivial functions like `-> true` or `-> it.thing.otherThing.value`, as they become very short. However it is a foot-gun when used with lodash's `_.each` methods, since it's easy to accidentally return a falsey value from your iteratee function, which is lodash's equivalent of `break`. My feet have lots of holes from that one.

Thence, it is helpful to notice the existence of the `!->` variation of the function-defining arrow. This suppresses the implicit return, preventing such madness. It also makes a clearer distinction between map-y code and side-effect-y code, which is (subjectively) nice.


Good luck and have fun!
