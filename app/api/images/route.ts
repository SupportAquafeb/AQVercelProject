import fs from "fs/promises";
import { NextResponse } from "next/server";

export const GET = async () => {
  try {
    // await fs.cp(
    //   "C:/Users/gcobc/Desktop/aquafeb0729/0729",
    //   "public" + "/images",
    //   {
    //     recursive: true,
    //   }
    // );
    const files = await fs.readdir("public" + "/images");
    return NextResponse.json(files);
  } catch (error) {
    console.error(error);
  }
};
