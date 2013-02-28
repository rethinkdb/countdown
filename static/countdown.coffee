# Returns a comma-separated list of the provided array
Handlebars.registerHelper 'comma_separated', (context) ->
    out = ""
    for i in [0...context.length]
        out += context[i]
        out += ", " if i isnt context.length-1
    return out

# Set the day boundaries for the graph
day_areas = (axes) ->
    markings = []
    d = new Date(axes.xaxis.min)
    # go to midnight at the timezone we're in locally
    d.setUTCSeconds(0)
    d.setUTCMinutes(0)
    d.setUTCHours(d.getTimezoneOffset() / 60)
    i = d.getTime()
    
    loop
        # when we don't set yaxis, the rectangle automatically
        # extends to infinity upwards and downwards
        markings.push
            xaxis:
                from: i
                to: i + 24 * 60 * 60 * 1000
            color: '#E0E0E0'
        i += 2 * 24 * 60 * 60 * 1000
        break if i >= axes.xaxis.max

    return markings

correct_for_timezone = (date) -> new Date(date.getTime() + date.getTimezoneOffset() * 60 * 1000)

# Compact reports for multiple milestones into one milestone
compact_reports = (reports) ->
    compact_report =
        open_issues: 0
        closed_issues: 0
        datetime: reports[0].datetime
        milestones: []
        user_stats: []

    # Compact the data points
    for report in reports
        compact_report.open_issues += report.open_issues
        compact_report.closed_issues += report.closed_issues
        compact_report.milestones.push report.milestone
        for user_stat in report.user_stats
            # Try to find an existing stat for this user, and add on the data
            matched_user = false
            for existing in compact_report.user_stats
                if existing.owner is user_stat.owner
                    console.log existing.owner, user_stat.owner
                    existing.open_issues += user_stat.open_issues
                    existing.closed_issues += user_stat.closed_issues
                    matched_user = true
                    break

            # If we haven't already compacted numbers for this user, create a new stat in the compact report
            compact_report.user_stats.push user_stat unless matched_user
          
    return compact_report

$ ->
    templates =
        summary: Handlebars.compile $('#summary-template').html()
        leaderboard: Handlebars.compile $('#leaderboard-template').html()
    $plot = $('#chart')
    $summary = $('#summary')
    $leaderboard = $('#leaderboard')
    $open_issues = $('.open-issues')
    $closed_issues = $('.closed-issues')
    $days_left = $('.days-left')

    # Update the width of the plot every time the window is resized
    $(window).resize ->
        $plot.css
            height: $(window).height() * 0.95

    # Repaint DOM elements and update the graph
    update = ->
        $.getJSON '/latest', (milestone_report) ->
            # Compact the report
            report = compact_reports milestone_report
            $summary.html templates['summary']
                open_issues: report.open_issues
                closed_issues: report.closed_issues
                days_left: Math.floor((deadline - new Date report.datetime)/1000/24/60/60) + 2
                progress_percent: Math.floor(report.closed_issues / (report.open_issues + report.closed_issues) * 100)
                milestones: report.milestones

            report.user_stats.sort (a,b) -> b.open_issues - a.open_issues

            $leaderboard.html templates['leaderboard']
               users: report.user_stats
        $.getJSON '/get_data', (milestone_reports) ->
            # Compact each of the reports
            reports = _.map milestone_reports, (milestone_report) ->
                compact_reports milestone_report

            data = _.map reports, (report) ->
                return [new Date(report.datetime), report.open_issues]

            $.plot $plot, [data],
                series:
                    color: '#A51026'
                    lines: { show: true }
                    points:
                        show: true
                        fill: true
                        fillColor: 'rgba(165, 16, 38, 0.2)'
                    shadowSize: 0
                xaxis:
                    mode: 'time'
                    twelveHourClock: true
                    timeformat: "%b %e, %l:%M %p" 
                    tickLength: 8
                    timezone: 'browser'
                yaxis:
                    minTickSize: 1
                    tickDecimals: 0
                grid:
                    markings: day_areas

            $plot.resize()

    # Get the deadline and kick off the application
    $.getJSON '/get_deadline', (data) ->
        window.deadline = correct_for_timezone(new Date data.deadline)
        update()
        setInterval(update, 60000)
