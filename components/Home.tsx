"use client";
import Link from "next/link";
import React, { useEffect, useState } from "react";

const Home = () => {
  const [images, setImages] = useState<string[]>([]);
  useEffect(() => {
    const fetchImages = async () => {
      try {
        const res = await fetch("/api/images");
        const data = await res.json();
        setImages(data);
      } catch (error) {
        console.error("Error:", error);
      }
    };

    fetchImages();
  }, []);

  return (
    <ul>
      {images.map((image) => {
        return (
          <li key={image}>
            <Link
              href={"https://aq-vercel-project.vercel.app/images/" + image}
              className="underline decoration-indigo-500 text-red-500"
            >
              {"https://aq-vercel-project.vercel.app/images/" + image}
            </Link>
          </li>
        );
      })}
    </ul>
  );
};

export default Home;
