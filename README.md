Countdown
=========

Installation
============

```
pip install Flask
pip install Flask-Assets
pip install rethinkdb
pip install apscheduler
pip install requests
pip install pyyaml
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

License
=======
Countdown is licensed under the MIT license: http://opensource.org/licenses/mit-license.php
