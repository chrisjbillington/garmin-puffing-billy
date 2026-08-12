import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class PuffingBillyApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    //! A data field app returns exactly one view: the field itself.
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new PuffingBillyField()];
    }
}
