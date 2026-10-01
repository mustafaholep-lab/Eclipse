"""Run the app's pure Continue Watching policy with Swift on the build host."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / 'Eclipse/Tracking/Progress/ProgressManager.swift').read_text(encoding='utf-8')
policy = source.split('enum ContinueWatchingPolicy {', 1)[1].split('\nstruct ContinueWatchingItem:', 1)[0]
checks = r'''
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
// Loki S02E03 must remain resumable after the tracker marks 85% watched.
check(ContinueWatchingPolicy.canResume(currentTime: 2550, duration: 3000), "85% vanished")
check(ContinueWatchingPolicy.canResume(currentTime: 2700, duration: 3000), "90% vanished")
check(!ContinueWatchingPolicy.canResume(currentTime: 2850, duration: 3000), "95% must advance")
check(!ContinueWatchingPolicy.canResume(currentTime: 3000, duration: 3000), "Manual completion must advance")
check(ContinueWatchingPolicy.canResume(currentTime: 30, duration: 7200), "Early movie progress missing")
check(!ContinueWatchingPolicy.canResume(currentTime: 0, duration: 3000), "Unstarted item visible")
check(!ContinueWatchingPolicy.canResume(currentTime: .nan, duration: 3000), "NaN accepted")
check(!ContinueWatchingPolicy.canResume(currentTime: 50, duration: 0), "Unknown duration accepted")
struct Card {
    let key: String
    let episode: Int
    let updatedAt: Date
}
let resume = Card(key: "show_loki", episode: 3, updatedAt: Date(timeIntervalSince1970: 100))
let next = Card(key: "show_loki", episode: 4, updatedAt: Date(timeIntervalSince1970: 101))
let movie = Card(key: "movie_loki", episode: 0, updatedAt: Date(timeIntervalSince1970: 99))
func merged(_ resume: [Card], _ next: [Card], limit: Int = 10) -> [Card] {
    ContinueWatchingPolicy.merged(resume: resume, next: next, key: { $0.key }, updatedAt: { $0.updatedAt }, limit: limit)
}
check(merged([resume], [next]).count == 1, "Duplicate show card")
check(merged([resume], [next])[0].episode == 3, "Next episode overrode saved position")
check(merged([], [next])[0].episode == 4, "Completed show vanished instead of advancing")
check(merged([movie, resume], [next]).map(\.key) == ["show_loki", "movie_loki"], "Wrong ordering or movie/show collision")
check(merged([resume], [next], limit: 0).isEmpty, "Zero limit ignored")
print("Continue Watching: 13 regression checks passed")
'''
with tempfile.TemporaryDirectory() as directory:
    test = pathlib.Path(directory) / 'main.swift'
    test.write_text('import Foundation\nenum ContinueWatchingPolicy {' + policy + checks, encoding='utf-8')
    subprocess.run(['swift', str(test)], check=True)
