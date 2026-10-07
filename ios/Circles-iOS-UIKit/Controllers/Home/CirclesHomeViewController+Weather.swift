import UIKit
import FavWidgets
import FavWidgetsCore

/// The temperature in the home header, between the left (help, connect) and
/// right (bell…) buttons (Wes, 2026-10-07). Current location or the place
/// picked in the Weather widget; tapping opens that widget. Forecasts are
/// cached ~15 min per km by `FavWeather`, so every appearance can ask.
extension CirclesHomeViewController {
    func setupWeatherHeader() {
        guard weatherHeaderObserver == nil else { return }
        weatherHeaderButton.addTarget(self, action: #selector(weatherHeaderTapped), for: .touchUpInside)
        weatherHeaderButton.isHidden = true   // until there's a reading
        navigationItem.titleView = weatherHeaderButton
        weatherHeaderObserver = FavWeather.shared.$header
            .receive(on: DispatchQueue.main)
            .sink { [weak self] header in self?.showWeatherHeader(header) }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshWeatherHeader),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        refreshWeatherHeader()
    }

    private func showWeatherHeader(_ header: FavWeather.Header?) {
        guard let header else { weatherHeaderButton.isHidden = true; return }
        weatherHeaderButton.configuration?.image = UIImage(systemName: header.symbolName)
        weatherHeaderButton.configuration?.attributedTitle = AttributedString(
            header.text, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 16, weight: .semibold)]))
        weatherHeaderButton.accessibilityLabel = header.accessibilityLabel
        weatherHeaderButton.isHidden = false
        weatherHeaderButton.sizeToFit()
    }

    @objc func refreshWeatherHeader() {
        Task { @MainActor in
            await FavWeather.shared.refresh { await Self.weatherLocation() }
        }
    }

    @objc private func weatherHeaderTapped() {
        AnalyticsService.shared.logEvent("weather_header_tapped", parameters: [:])
        showWidgetsTab(openingWidget: "weather")
    }

    /// One fix from the app's LocationService (nil if denied or it stalls)
    private static func weatherLocation() async -> WidgetCoordinate? {
        await withCheckedContinuation { continuation in
            let once = OnceFlag()
            LocationService.shared.getCurrentLocation { location in
                guard once.claim() else { return }
                continuation.resume(returning: location.map {
                    WidgetCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                })
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                guard once.claim() else { return }
                continuation.resume(returning: nil)
            }
        }
    }
}
