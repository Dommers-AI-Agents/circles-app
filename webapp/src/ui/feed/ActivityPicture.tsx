// The picture on every Activity card: the photo, else a still map of the
// pin (map tiles as plain images), else a drawn poster. A photo that fails
// to load falls to the next thing the row has, so no card is ever blank.
import { useState } from 'react';
import type { Picture, Poster } from '../../logic/activityCopy';
import { tilesAround, tileUrl } from '../../logic/mapTiles';
import { TILES } from '../../map/tiles';

/** Wide enough for the widest card; the box crops it to its own width. */
const MAP_W = 760;
const MAP_H = 220;
const MAP_ZOOM = 16;

export function StaticMap({ lat, lng }: { lat: number; lng: number }) {
  const tiles = tilesAround(lat, lng, MAP_ZOOM, MAP_W, MAP_H);
  return (
    <div className="feed-map" aria-label="Map of where this happened" role="img">
      <div className="feed-map-tiles">
        {tiles.map((tile) => (
          <img key={`${tile.x}-${tile.y}`} src={tileUrl(TILES.url, tile)} alt="" loading="lazy" draggable={false}
            style={{ left: tile.left, top: tile.top }} />
        ))}
      </div>
      <span className="feed-map-pin" aria-hidden="true" />
      <span className="feed-map-credit">© OpenStreetMap</span>
    </div>
  );
}

export function PosterPicture({ poster }: { poster: Poster }) {
  return (
    <div className={`feed-poster tint-${poster.tint}`}>
      <span className="feed-poster-mark" aria-hidden="true">{poster.mark}</span>
      <strong className="feed-poster-title">{poster.title}</strong>
      {poster.detail ? <span className="feed-poster-detail">{poster.detail}</span> : null}
    </div>
  );
}

export function ActivityPicture({ pictures, poster, chip }: { pictures: Picture[]; poster: Poster; chip: string | null }) {
  const [failed, setFailed] = useState(0);
  const picture = pictures[failed];
  return (
    <div className="feed-picture">
      {picture?.kind === 'photo' ? (
        <img className="feed-photo" src={picture.url} alt="" loading="lazy" onError={() => setFailed((n) => n + 1)} />
      ) : picture?.kind === 'map' ? (
        <StaticMap lat={picture.lat} lng={picture.lng} />
      ) : (
        <PosterPicture poster={poster} />
      )}
      {chip ? <span className="feed-chip">{chip}</span> : null}
    </div>
  );
}
