# CouchDB Footrest

Not comfortable enough on the couch? Pull up footrest.

## Install

1) Have the latest Erlang OTP (>= 5.7).
2) Install CouchDB.
3) Edit your /etc/couchdb/local.ini appending the following line:
    [external]
    footrest = /path/to/src/couchdb-footrest/footrest

    [httpd_db_handlers]
    _footrest = {couch_httpd_external, handle_external_req, <<"footrest">>}


## Usage

To use Footrest, throw in a "_footrest" in the path of the queries you make to CouchDB. For example:

    http://localhost:5984/dbname/_footrest/_all_docs

Of course, that doesn't do anything but give you the exact same results you would have had without the "_footrest". Here's what you can do with Footrest that you can't do with CouchDB alone:

### Only Include Docs of Particular IDs

Ever need to just intersect the results of a view with relevant Doc IDs? Footrest has got you covered:

    http://localhost:5984/dbname/_footrest/_design/Posts/_view/by_text?key="love"&only_include=["004a33cf430771b0099ee01731eaec53", ... ,"014832b4bcca92488436b72ed67a1a56"]

Note that the results will be ordered in the same order that the Doc IDs are given, unless...

### Order Docs By Value Fields

Ever need to order results by something other than the key you're segmenting the data with? Footrest makes that easy too:

    http://localhost:5984/loudly_dev/_footrest/_all_docs?startkey="00"&endkey="10"&order_by=["created_at","asc"]


## Future Features

Want to help out? Here are some features we plan to implement and that you might want to work on:

### Result Storage and Intersection

Love Footrest but hate passing around thousands of IDs? Here's the plan: we're going to allow users of Footrest to cache results in a separate database and then use those results directly from Footrest as need. For instance, imagine you want to retrieve all the posts containing a particular word between particular dates:

    http://localhost:5984/dbname/_footrest/_design/Posts/_view/by_date?startkey="2009"&endkey="2010"&store_as="posts-by-date-2009-2010"

    http://localhost:5984/dbname/_footrest/_design/Posts/_view/by_text?key="love"&only_include="posts-by-date-2009-2010"

