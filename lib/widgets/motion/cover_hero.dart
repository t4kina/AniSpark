/// The hero tag for media [mediaId]'s cover shown by the list [scope], e.g.
/// `coverHeroTag('home-trending', 21)`. Pass it to both the list's `Hero`
/// and `DetailScreen(heroTag: ...)` so the cover flies between them.
///
/// The scope must be unique on its screen: Discover can show the same
/// media in several rows, and two heroes with one tag on a page break the
/// transition.
String coverHeroTag(String scope, int mediaId) => 'cover:$scope:$mediaId';
