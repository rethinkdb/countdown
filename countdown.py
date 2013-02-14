#! /usr/bin/env python
from flask import Flask, g, render_template
from flask.ext.assets import Environment, Bundle
from rethinkdb import r
import requests
import json
import yaml
from apscheduler.scheduler import Scheduler
import logging
import datetime
import sys

# Configuration and static variables
config = yaml.load(open('config.yaml'))
HEADERS = {'Authorization': 'token ' + config['oauth']}
URL = 'https://api.github.com/repos/'+config['repo']
MILESTONE = config['milestone']
STATS_TABLE = 'stats'
ISSUES_TABLE = 'issues'

# Simple utility functions
def connect_to_db():
    return r.connect(host=config['rethinkdb']['host'], port=config['rethinkdb']['port'], db_name=config['rethinkdb']['db'])

def update_data(check_for_existing_data=False):
    conn = connect_to_db()
    print "check for existing data: "+str(check_for_existing_data)
    print "count_issues: "+ str(r.table(ISSUES_TABLE).count().run()) 
    print "count stats: "+ str(r.table(STATS_TABLE).count().run())
    print "boolean: "+ str(not check_for_existing_data or (check_for_existing_data and r.table(ISSUES_TABLE).count().run() == 0))
    if not check_for_existing_data or (check_for_existing_data and r.table(ISSUES_TABLE).count().run() == 0):
        pull_new_issues(conn)
    if not check_for_existing_data or (check_for_existing_data and r.table(STATS_TABLE).count().run() == 0):
        generate_stats(conn)
    conn.close()
    

def pull_new_issues(rdb_conn):
    issues = []
    print "Pulling issues from Github..."

    for state in ['open','closed']:
        page_num = 0
        while True:
            url = "%s/issues?page=%d&state=%s" % (URL, page_num, state)
            sys.stdout.write("Processing page %d of issues...   \r" % page_num)
            sys.stdout.flush()
            gh_issue_set = requests.get(url=url, headers=HEADERS).json

            if 'message' in gh_issue_set and gh_issue_set['message'] == 'Not Found':
                print "No issues found for the %s repository." % config['repo']
                return

            if gh_issue_set == []:
                break

            issues += gh_issue_set
            page_num += 1

        print "Pulled %d issues from Github that are %s." % (len(issues),state)
    print "Pulled a total of %d issues." % len(issues)
    r.table(ISSUES_TABLE).delete().run(rdb_conn)
    r.table(ISSUES_TABLE).insert(issues).run(rdb_conn)
    num_inserted = r.table(ISSUES_TABLE).count().run()
    print "Inserted %d issues into RethinkDB." % num_inserted

def generate_stats(rdb_conn):
    issues = r.table(ISSUES_TABLE)
    issues_with_milestone = issues.filter(lambda issue: issue['milestone'] != None)
    milestones = issues_with_milestone.map(lambda issue: issue['milestone']['title']).distinct()

    # Generate user stats (how many issues assigned to this user have been opened and closed) for a particular set of issues
    def user_stats(issue_set):
        # Remove issues that don't have owners from the issue set
        issue_set = issue_set.filter(lambda issue: issue['assignee'] != None)

        # Get a list of users issues are assigned to
        owners = issue_set.map(lambda issue: issue['assignee']).distinct()
        
        # Count the issues with a given owner and state (shorthand since we reuse this)
        def count_issues(owner,state):
            return issue_set.filter(lambda issue: (issue['assignee']['login'] == owner['login']) & (issue['state'] == state)).count()

        # Return a list of documents with stats for each owner
        return owners.map(lambda owner: {
            'owner':    owner['login'],
            'owner_avatar_url': owner['avatar_url'],
            'open_issues': count_issues(owner,'open'),
            'closed_issues': count_issues(owner,'closed'),
        })

    # Return owner stats for a particular milestone (filter issues to just include a milestone)
    def user_stats_by_milestone(m):
        return user_stats(issues_with_milestone.filter(lambda issue: issue['milestone']['title'] == m))

    # Return the number of issues with a particular state (and optionally a particular milestone)
    def num_issues(state, milestone=None):
        if milestone is None:
            issue_set = issues
        else:
            issue_set = issues_with_milestone.filter(lambda issue: issue['milestone']['title'] == milestone)
        return issue_set.filter(lambda issue: issue['state'] == state).count()

    # Two key things:
    # - we have to call stream_to_array since this a stream, and this will error otherwise
    # - we have to call list() on the stats to make sure we pull down all the data from a BatchedIterator
    report = r.expr({
        'datetime': r.js('(new Date).toISOString()'),
        'by_milestone': r.union(r.expr([{
            'milestone': 'all',
            'open_issues': num_issues('open'),
            'closed_issues': num_issues('closed'),
            'user_stats': user_stats(issues).stream_to_array()
        }]).array_to_stream(), milestones.map(lambda m: {
            'milestone': m,
            'open_issues': num_issues('open', m),
            'closed_issues': num_issues('closed', m),
            'user_stats': user_stats_by_milestone(m).stream_to_array()
        })).stream_to_array()
    })

    # Add the generated report to the database
    print "Generating and inserting new user stats at %s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    r.table(STATS_TABLE).insert(r.expr([report]).array_to_stream()).run(rdb_conn)

# Flask application
app = Flask(__name__)
assets = Environment(app)

bundle_less = Bundle('countdown.less', filters='less', output='gen/countdown.css')
assets.register('countdown_css', bundle_less)

bundle_coffee = Bundle('countdown.coffee', filters='coffeescript', output='gen/countdown.js')
assets.register('countdown_js', bundle_coffee)

bundle_js = Bundle('vendor/jquery-1.9.1.min.js',
            'vendor/jquery.flot.js',
            'vendor/jquery.flot.time.js',
            'vendor/jquery.flot.resize.js',
            'vendor/underscore-min.js',
            'vendor/bootstrap.min.js',
            'vendor/handlebars.js',
            'vendor/swag.min.js',
        filters='rjsmin', output='gen/vendor.js')
assets.register('vendor_js', bundle_js)

@app.before_request
def before_request():
    g.rdb_conn = connect_to_db()

@app.teardown_request
def teardown_request(exception):
    g.rdb_conn.close()

@app.route('/')
def index():
    return render_template('countdown.html')

@app.route('/get_data')
def get_data():
    selection = list(r.table(STATS_TABLE).order_by('datetime').map(lambda report:
        report['by_milestone'].filter(lambda report_by_m:
            report_by_m['milestone'] == MILESTONE
        ).map(lambda filtered_report:
            filtered_report.merge({'datetime': report['datetime']})
        )[0]).run(g.rdb_conn))
    return json.dumps(selection)

@app.route('/latest')
def latest():
    last_report = r.table(STATS_TABLE).order_by(r.desc('datetime'))[0]
    selection = last_report['by_milestone'].filter(lambda report_by_m:
            report_by_m['milestone'] == MILESTONE
    )[0].merge({'datetime': last_report['datetime']}).run(g.rdb_conn)
    return json.dumps(selection)

@app.route('/get_deadline')
def get_deadline():
    return json.dumps({
        'deadline': config['deadline'],
        'milestone': config['milestone']
    })

# Process to get the new data points
logging.basicConfig(level=logging.DEBUG)
sched = Scheduler()

@sched.interval_schedule(minutes=10)
def timed_job():
    update_data()

# Kick everything off
if __name__ == '__main__':
    conn = connect_to_db()
    generate_stats(conn)
    conn.close()
    sched.start()
    update_data(check_for_existing_data=True)
    app.run()
