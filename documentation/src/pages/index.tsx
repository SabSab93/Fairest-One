import type {ReactNode} from 'react';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import styles from './index.module.css';

const chapters = [
  {
    number: '01',
    title: 'Cadrer',
    text: 'Poser l’idée, rassembler les références et établir la nomenclature du prototype.',
    link: '/construction/idee-et-inspirations',
  },
  {
    number: '02',
    title: 'Concevoir',
    text: 'Mesurer les composants, dessiner les premières pistes et construire les pièces en 3D.',
    link: '/construction/releves-dimensionnels',
  },
  {
    number: '03',
    title: 'Fabriquer',
    text: 'Imprimer, câbler, programmer puis documenter l’assemblage du miroir.',
    link: '/construction/impression-3d',
  },
];

export default function Home(): ReactNode {
  return (
    <Layout
      title="Journal de conception"
      description="Construction du prototype de miroir connecté Fairest One">
      <main>
        <section className={styles.hero}>
          <div className={styles.heroInner}>
            <p className={styles.eyebrow}>MIROIR CONNECTÉ · MASTER 2</p>
            <Heading as="h1">Fairest One</Heading>
            <p className={styles.lead}>
              Journal de conception d’un miroir connecté pour accompagner
              l’essayage de lunettes.
            </p>
            <Link className={styles.primaryAction} to="/construction/introduction">
              Explorer la construction <span aria-hidden="true">→</span>
            </Link>
          </div>
          <div className={styles.mirrorVisual} aria-hidden="true">
            <div className={styles.mirrorFrame}>
              <span>FO</span>
              <i />
            </div>
            <p>25 × 30 cm</p>
          </div>
        </section>

        <section className={styles.statement}>
          <p>DE L’IDÉE À L’OBJET</p>
          <Heading as="h2">
            Chaque décision,
            <br />
            mesure et essai.
          </Heading>
          <span>
            Une documentation progressive, complétée au rythme de la
            fabrication réelle du prototype.
          </span>
        </section>

        <section className={styles.chapters}>
          {chapters.map((chapter) => (
            <Link to={chapter.link} className={styles.chapter} key={chapter.number}>
              <span className={styles.chapterNumber}>{chapter.number}</span>
              <Heading as="h3">{chapter.title}</Heading>
              <p>{chapter.text}</p>
              <span className={styles.chapterArrow} aria-hidden="true">↗</span>
            </Link>
          ))}
        </section>

        <section className={styles.budget}>
          <div>
            <p className={styles.eyebrow}>BOM · PROTOTYPE MINIMUM</p>
            <Heading as="h2">119,34 €</Heading>
          </div>
          <p>
            63,55 € pour le miroir et 55,79 € pour la borne tablette, d’après
            la nomenclature actuelle.
          </p>
          <Link to="/construction/bom">Voir les composants →</Link>
        </section>
      </main>
    </Layout>
  );
}
