/// The hero tag for media [mediaId]'s cover shown by the list [scope], e.g.
/// `coverHeroTag('home-trending', 21)`. Pass it to both the list's `Hero`
/// and `DetailScreen(heroTag: ...)` so the cover flies between them.
///
/// The scope must be unique on its screen: Discover can show the same
/// media in several rows, and two heroes with one tag on a page break the
/// transition.
String coverHeroTag(String scope, int mediaId) => 'cover:$scope:$mediaId';

/// The hero tag for the picture of the character, staff member or user
/// [id] shown by [scope], e.g. `personHeroTag('detail-21-characters', 40)`.
/// Pass it to the picture that is tapped and to the page it opens, so the
/// picture flies there. As with covers, the scope must be unique on its
/// screen: a feed shows the same avatar on every post by that user.
String personHeroTag(String scope, int id) => 'person:$scope:$id';
