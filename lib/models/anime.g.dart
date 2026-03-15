// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'anime.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AnimeAdapter extends TypeAdapter<Anime> {
  @override
  final int typeId = 0;

  @override
  Anime read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Anime(
      id: fields[0] as int,
      title: fields[1] as String,
      coverImage: fields[2] as String?,
      episodes: fields[3] as int?,
      status: fields[4] as String,
      episodesWatched: fields[5] as int,
      userScore: fields[6] as int?,
      description: fields[7] as String?,
      averageScore: fields[8] as double?,
      genres: (fields[9] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Anime obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.coverImage)
      ..writeByte(3)
      ..write(obj.episodes)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.episodesWatched)
      ..writeByte(6)
      ..write(obj.userScore)
      ..writeByte(7)
      ..write(obj.description)
      ..writeByte(8)
      ..write(obj.averageScore)
      ..writeByte(9)
      ..write(obj.genres);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnimeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
