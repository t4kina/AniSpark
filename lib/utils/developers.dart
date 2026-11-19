/// AniList users who make AniSpark, by their AniList name in lower case.
/// AniList names are unique; if one is changed, change it here too.
const _developerNames = {'t4kina'};

/// Whether [name], an AniList user name, is one of AniSpark's developers,
/// who get the developer seal beside their name everywhere it is shown.
bool isAniSparkDeveloper(String? name) =>
    name != null && _developerNames.contains(name.trim().toLowerCase());
