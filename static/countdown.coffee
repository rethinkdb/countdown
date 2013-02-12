$ ->
    # Set the day boundaries for the graph
    day_areas = (axes) ->
        markings = []
        d = new Date(axes.xaxis.min)
        # go to the first Saturday
        d.setUTCSeconds(0)
        d.setUTCMinutes(0)
        d.setUTCHours(13)
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

    $plot = $('#chart')
    $open_issues = $('.open-issues')
    $closed_issues = $('.closed-issues')
    $days_left = $('.days-left')

    # Update the width of the plot every time the window is resized
    $(window).resize -> 
        $plot.css
            height: $(window).height() * 0.95

    # Repaint DOM elements and update the graph
    update = -> $.getJSON '/get_data', (reports) ->
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
                minTickSize: [1, "day"]
                tickLength: 5
                timezone: 'browser'
            grid:
                markings: day_areas

            $.getJSON '/latest', (report) ->
                $open_issues.text report.open_issues
                $closed_issues.text report.closed_issues
                days_left = (deadline - (new Date report.datetime))/1000/24/60/60
                $days_left.text Math.floor(days_left)

        $plot.resize()

    # Get the deadline and kick off the application
    $.getJSON '/get_deadline', (data) ->
        window.deadline = new Date(data.deadline)
        update()
        setInterval(update, 60000)
