Countdown
=========

Installation
============

If you don't already have RethinkDB, [go download](http://rethinkdb.com/docs/install) and install it.

Install the required libraries:
```
npm install -g less
npm install -g coffee-script
pip install -r requirements.txt
```

Deploying
=========

Countdown uses the CherryPy WSGI server, as it's lightweight and easy to deploy. Start an instance of RethinkDB, and then launch Countdown with:

```
python countdown.py
```

If you want to deploy this on port 80, you can use nginx (or other web server) as a proxy. Here's an example nginx config:
```
server {
        listen          80;
        server_name     $hostname;

        location / {
            proxy_pass http://127.0.0.1:8888/;
        }
}

```

Important notes
===============
Countdown was built with RethinkDB 1.3 ("Metropolis"), which had several outstanding ReQL quirks and bugs. As a result, the queries it employs are more complicated and cumbersome than necessary. A rewrite after RethinkDB 1.4 is released will happen, since the query language in that version is significantly improved.

License
=======
Countdown is licensed under the MIT license: http://opensource.org/licenses/mit-license.php
