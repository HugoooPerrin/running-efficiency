using Toybox.Activity;
using Toybox.Lang;
using Toybox.Time;
using Toybox.WatchUi;
using Toybox.Math;
using Toybox.Application;
using Toybox.FitContributor;


// GAP modelling
// ref : https://www.reddit.com/r/Strava/comments/sdeix0/mind_the_gap_getting_fit_for_the_formula_equation/
function grade_factor(g) {
    return 1 + 0.02869556 * g + 0.001520768 * g * g;
}

// Aerobic efficiency : DONE 
// Aerobic decoupling : ??
// Aerobic deviation (vs baseline) : ??



// MAIN DATA FIELD CLASS
class RunningEfficiencyView extends WatchUi.SimpleDataField {

    // General settings
    var ignore_first;
    var lag = 0;

    // Application settings
    var metric_id;
    var rFTP;
    var LTHR;
    var threshold_factor;
    var normalizing_constant;
    var rolling_duration;
    var rolling_duration_grade;

    // Fit fields
    var efficiencyFitField;

    // Set the label of the data field here.
    function initialize() {
        SimpleDataField.initialize();

        // Collect user settings
        metric_id = Application.getApp().getProperty("METRIC_ID").toNumber();
        normalizing_constant = Application.getApp().getProperty("NORM").toFloat();
        
        rolling_duration = Application.getApp().getProperty("WINDOW").toNumber()+1;
        rolling_duration_grade = Application.getApp().getProperty("WINDOW_GRADE").toNumber()+1;

        ignore_first = Application.getApp().getProperty("SKIP_FIRST").toNumber();

        // Rolling windows security net
        rolling_duration_grade = (rolling_duration < rolling_duration_grade) ? rolling_duration : rolling_duration_grade;

        // Chosen metric
        LTHR = Application.getApp().getProperty("LTHR").toNumber();
        if (metric_id == 0) {
            rFTP = Application.getApp().getProperty("RFTP").toFloat();
        } else {
            rFTP = Application.getApp().getProperty("RFTPa").toFloat();
        }
        label = "EFFICIENCY";

        // Threshold factor
        threshold_factor = (rFTP / LTHR) / normalizing_constant;

        // GRAPH FIT FIELDS
        // Create the custom efficiency FIT data field we want to record
        efficiencyFitField = createField(
            "Running efficiency",
            0,
            FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD, :units=>""}
        );
        efficiencyFitField.setData(0);

        // LAP FIT FIELDS : TO COME !!
        // OVERALL FIT FIELDS : TO COME !!
    }

    // Reset metric queue & lag when starting or restarting activity
    // (to prevent from decreasing value while effort is increasing since resuming activity)
    function reset_queues(lag_duration) {
        heart_rate = new Queue(rolling_duration);

        if (metric_id == 0) {
            power = new Queue(rolling_duration);

        } else if (metric_id == 1) {
            speed = new Queue(rolling_duration);

        } else if (metric_id == 2) {
            altitude = new Queue(rolling_duration_grade);
            speed = new Queue(rolling_duration);
            gap = new Queue(rolling_duration);

        }
        lag = ignore_first - lag_duration;
    }

    function onTimerStart() {
        reset_queues(ignore_first);
    }

    function onTimerResume() {
        reset_queues(30);
    }

    // Reset metric queue when starting a new workout step (NOT A SIMPLE LAP)
    // to be directly accurate related to targeted effort
    function onWorkoutStepComplete() {
        reset_queues(60);
    }

    // Computing variable
    var power;
    var heart_rate;
    var speed;
    var altitude;
    var grade;
    var gap;
    var instant_gap;
    var dist;
    var n_seconds;
    var rolling_input;
    var rolling_output;
    var running_efficiency;
    var val;

    // The given info object contains all the current workout
    // information. Calculate a value and return it in this method.
    // Note that compute() and onUpdate() are asynchronous, and there is no
    // guarantee that compute() will be called before onUpdate().
    function compute(info as Activity.Info) as Numeric or Duration or String or Null {

        // Update rolling queues, compute value & save to fit file
        if (lag >= ignore_first) {

            // Heart rate
            heart_rate.update((info.currentHeartRate != null) ? info.currentHeartRate : 0);
            rolling_input = heart_rate.mean();

            // Power based efficiency
            if (metric_id == 0) {
                power.update((info.currentPower != null) ? info.currentPower : 0);
                rolling_output = power.mean();

            // Pace base efficiency
            } else if (metric_id == 1) {
                speed.update((info.currentSpeed != null) ? info.currentSpeed : 0);
                rolling_output = speed.mean();

            // GAP based efficiency
            } else if (metric_id == 2) {
                speed.update((info.currentSpeed != null) ? info.currentSpeed : 0);
                altitude.update((info.altitude != null) ? info.altitude : 0);

                // INSTANT GRADE AND GAP
                // Count how many values are stored in altitude queue 
                // (potentially shorter than other : rolling_duration_grade <= rolling_duration)
                n_seconds = altitude.count_not_null();

                // Get distance estimate using enhanced speed (mps)
                dist = speed.current(n_seconds) * n_seconds;

                // Compute instant grade (%) and clip to 40% to prevent abnormal values
                grade = ((n_seconds >= 5) & (dist > 1)) ? 100 * (altitude.current(2) - altitude.last(2)) / dist : 0;
                grade = (grade < 40) ? grade : 40;
                grade = (grade > -40) ? grade : -40;

                // GAP
                instant_gap = speed.current(1) * grade_factor(grade);
                gap.update(instant_gap);
                rolling_output = gap.mean();
            }

            // Saving rolling Running Efficiency to fit file
            running_efficiency = (rolling_output != 0) ? (rolling_input / rolling_output) * threshold_factor : 1;
            efficiencyFitField.setData(running_efficiency);

            val = running_efficiency.format("%.2f");

        } else if (info.timerState == 3) {
            // Increase lag counter
            lag++;
            val = "--";

        } else {
            val = "--";
        }
        
        return val;
    }
}