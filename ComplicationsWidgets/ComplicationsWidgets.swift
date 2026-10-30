import SwiftUI
import WidgetKit

@main
struct ComplicationsWidgets: WidgetBundle {
    var body: some Widget {
        CalendarComplication()
        BatteryComplication()
        WeatherComplication()
    }
}
