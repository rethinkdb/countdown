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
        $.getJSON '/latest', (report) ->
            $summary.html templates['summary']
                open_issues: _.reduce(report, (total_open, milestone) ->
                    console.log 'total',total_open
                    console.log milestone.open_issues
                    total_open = total_open + milestone.open_issues
                , 0)
                closed_issues: _.reduce(report, (total_closed, milestone) ->
                     total_closed = total_closed + milestone.closed_issues
                )
                days_left: Math.floor((deadline - new Date report.datetime)/1000/24/60/60) + 1
                progress_percent: Math.floor(report.closed_issues / (report.open_issues + report.closed_issues) * 100)
            report.user_stats.sort (a,b) ->
                div_a = (a.open_issues + 1) / (a.closed_issues + 1)
                div_b = (b.open_issues + 1) / (b.closed_issues + 1)
                # If the fraction is the same, rank the one with more closed issues higher
                if div_a == div_b
                    return b.closed_issues - a.closed_issues
                return div_a - div_b

            $leaderboard.html templates['leaderboard']
               users: report.user_stats
        $.getJSON '/get_data', (reports) ->
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
